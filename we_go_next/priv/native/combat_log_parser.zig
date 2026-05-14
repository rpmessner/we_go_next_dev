const std = @import("std");
const beam = @import("beam");
const e = @import("erl_nif");

// =========================================================================
// scan_boundaries NIF
// =========================================================================

pub fn scan_boundaries(file_path_term: beam.term, start_byte_term: beam.term) beam.term {
    const env = beam.context.env orelse unreachable;

    // Get arguments
    const file_path = beam.get([]const u8, file_path_term, .{}) catch {
        return make_error_tuple(env, "invalid_file_path");
    };
    const start_byte = beam.get(u64, start_byte_term, .{}) catch {
        return make_error_tuple(env, "invalid_start_byte");
    };

    // Open file
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        return make_error_tuple(env, "file_not_found");
    };
    defer file.close();

    // Get file size
    const stat = file.stat() catch {
        return make_error_tuple(env, "stat_failed");
    };
    _ = stat.size;

    // Seek to start position
    file.seekTo(start_byte) catch {
        return make_error_tuple(env, "seek_failed");
    };

    // Note: we do NOT skip to line boundary here because our saved
    // positions (last_valid_pos / last_parsed_byte) are always at line
    // boundaries. Skipping would miss the first line of appended content.

    // Scan for boundaries - use raw ErlNifTerm for list building
    var boundaries_list: e.ErlNifTerm = e.enif_make_list(env, 0);
    var boundary_count: u32 = 0;
    var current_start: ?u64 = null;
    var current_encounter_id: [64]u8 = undefined;
    var current_encounter_id_len: usize = 0;
    var current_name: [256]u8 = undefined;
    var current_name_len: usize = 0;
    var current_difficulty_id: i32 = 0;
    var current_group_size: i32 = 0;
    var current_instance_id: [64]u8 = undefined;
    var current_instance_id_len: usize = 0;
    var current_start_ts: [64]u8 = undefined;
    var current_start_ts_len: usize = 0;

    var buf: [65536]u8 = undefined;
    var line_buf: [16384]u8 = undefined;
    var line_len: usize = 0;
    var last_valid_pos = file.getPos() catch start_byte;

    // Read file in chunks
    while (true) {
        const bytes_read = file.read(&buf) catch break;
        if (bytes_read == 0) break;

        var i: usize = 0;
        while (i < bytes_read) {
            if (buf[i] == '\n') {
                // Strip trailing \r (Windows CRLF)
                if (line_len > 0 and line_buf[line_len - 1] == '\r') {
                    line_len -= 1;
                }
                // Complete line
                if (line_len > 0) {
                    const line = line_buf[0..line_len];
                    const current_pos = (file.getPos() catch break) - (bytes_read - i - 1);

                    if (is_encounter_start(line)) {
                        // Parse ENCOUNTER_START fields
                        current_start = last_valid_pos;
                        parse_encounter_start_fields(line, &current_encounter_id, &current_encounter_id_len, &current_name, &current_name_len, &current_difficulty_id, &current_group_size, &current_instance_id, &current_instance_id_len, &current_start_ts, &current_start_ts_len);
                    } else if (is_encounter_end(line) and current_start != null) {
                        // Parse ENCOUNTER_END and emit boundary
                        var success: bool = false;
                        var fight_time_ms: i64 = 0;
                        var end_ts: [64]u8 = undefined;
                        var end_ts_len: usize = 0;
                        parse_encounter_end_fields(line, &success, &fight_time_ms, &end_ts, &end_ts_len);

                        const boundary = make_boundary_map(env, current_encounter_id[0..current_encounter_id_len], current_name[0..current_name_len], current_difficulty_id, current_group_size, current_instance_id[0..current_instance_id_len], current_start.?, current_pos, current_start_ts[0..current_start_ts_len], end_ts[0..end_ts_len], success, fight_time_ms);

                        boundaries_list = e.enif_make_list_cell(env, boundary.v, boundaries_list);
                        boundary_count += 1;
                        current_start = null;
                    } else if (is_challenge_mode_start(line)) {
                        // Emit CHALLENGE_MODE_START boundary
                        var cm_name: [256]u8 = undefined;
                        var cm_name_len: usize = 0;
                        var cm_instance_id: [64]u8 = undefined;
                        var cm_instance_id_len: usize = 0;
                        var cm_id: i32 = 0;
                        var cm_level: i32 = 0;
                        var cm_ts: [64]u8 = undefined;
                        var cm_ts_len: usize = 0;
                        parse_challenge_mode_start_fields(line, &cm_name, &cm_name_len, &cm_instance_id, &cm_instance_id_len, &cm_id, &cm_level, &cm_ts, &cm_ts_len);

                        const cm_boundary = make_challenge_mode_start_map(env, cm_name[0..cm_name_len], cm_instance_id[0..cm_instance_id_len], cm_id, cm_level, last_valid_pos, cm_ts[0..cm_ts_len]);
                        boundaries_list = e.enif_make_list_cell(env, cm_boundary.v, boundaries_list);
                        boundary_count += 1;
                    } else if (is_challenge_mode_end(line)) {
                        // Emit CHALLENGE_MODE_END boundary
                        var cm_success: bool = false;
                        var cm_level: i32 = 0;
                        var cm_total_time: i64 = 0;
                        var cm_end_ts: [64]u8 = undefined;
                        var cm_end_ts_len: usize = 0;
                        parse_challenge_mode_end_fields(line, &cm_success, &cm_level, &cm_total_time, &cm_end_ts, &cm_end_ts_len);

                        const cm_boundary = make_challenge_mode_end_map(env, cm_success, cm_level, cm_total_time, current_pos, cm_end_ts[0..cm_end_ts_len]);
                        boundaries_list = e.enif_make_list_cell(env, cm_boundary.v, boundaries_list);
                        boundary_count += 1;
                    }

                    last_valid_pos = current_pos;
                }
                line_len = 0;
            } else {
                if (line_len < line_buf.len) {
                    line_buf[line_len] = buf[i];
                    line_len += 1;
                }
            }
            i += 1;
        }
    }

    // Reverse the list (we built it backwards with list_cell)
    var reversed: e.ErlNifTerm = e.enif_make_list(env, 0);
    var current_term = boundaries_list;
    var head: e.ErlNifTerm = undefined;
    var tail: e.ErlNifTerm = undefined;
    while (e.enif_get_list_cell(env, current_term, &head, &tail) != 0) {
        reversed = e.enif_make_list_cell(env, head, reversed);
        current_term = tail;
    }

    const end_byte_term = beam.make(last_valid_pos, .{});
    const reversed_term: beam.term = .{ .v = reversed };
    return beam.make(.{ .ok, reversed_term, end_byte_term }, .{});
}

// =========================================================================
// parse_events NIF
// =========================================================================

pub fn parse_events(file_path_term: beam.term, start_byte_term: beam.term, end_byte_term: beam.term, start_ts_term: beam.term) beam.term {
    const env = beam.context.env orelse unreachable;

    const file_path = beam.get([]const u8, file_path_term, .{}) catch {
        return make_error_tuple(env, "invalid_file_path");
    };
    const start_byte = beam.get(u64, start_byte_term, .{}) catch {
        return make_error_tuple(env, "invalid_start_byte");
    };
    const end_byte = beam.get(u64, end_byte_term, .{}) catch {
        return make_error_tuple(env, "invalid_end_byte");
    };
    const start_ts_str = beam.get([]const u8, start_ts_term, .{}) catch {
        return make_error_tuple(env, "invalid_start_timestamp");
    };

    const start_timestamp_us = parse_timestamp_to_us(start_ts_str) orelse {
        return make_error_tuple(env, "bad_start_timestamp");
    };

    // Open file and seek
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        return make_error_tuple(env, "file_not_found");
    };
    defer file.close();

    file.seekTo(start_byte) catch {
        return make_error_tuple(env, "seek_failed");
    };

    // Read all bytes in range
    const byte_count = end_byte - start_byte;
    const allocator = std.heap.page_allocator;
    const data = allocator.alloc(u8, byte_count) catch {
        return make_error_tuple(env, "alloc_failed");
    };
    defer allocator.free(data);

    const actual_read = file.readAll(data) catch {
        return make_error_tuple(env, "read_failed");
    };
    const content = data[0..actual_read];

    // Parse lines and build event list
    var events_list: e.ErlNifTerm = e.enif_make_list(env, 0);
    var event_count: u32 = 0;

    var line_start: usize = 0;
    for (content, 0..) |c, idx| {
        if (c == '\n') {
            // Strip trailing \r (Windows CRLF)
            var line_end = idx;
            if (line_end > line_start and content[line_end - 1] == '\r') {
                line_end -= 1;
            }
            const line = content[line_start..line_end];
            if (line.len > 10) {
                const event_term = parse_event_line(env, line, start_timestamp_us);
                if (event_term) |evt| {
                    events_list = e.enif_make_list_cell(env, evt.v, events_list);
                    event_count += 1;
                }
            }
            line_start = idx + 1;
        }
    }

    // Reverse the list
    var reversed: e.ErlNifTerm = e.enif_make_list(env, 0);
    var current_term = events_list;
    var head: e.ErlNifTerm = undefined;
    var tail: e.ErlNifTerm = undefined;
    while (e.enif_get_list_cell(env, current_term, &head, &tail) != 0) {
        reversed = e.enif_make_list_cell(env, head, reversed);
        current_term = tail;
    }

    const reversed_term: beam.term = .{ .v = reversed };
    return beam.make(.{ .ok, reversed_term }, .{});
}

// =========================================================================
// Line classification
// =========================================================================

fn is_encounter_start(line: []const u8) bool {
    // Find the double-space separator, then check event type
    const event_start = find_double_space(line) orelse return false;
    const rest = line[event_start..];
    return std.mem.startsWith(u8, rest, "ENCOUNTER_START,");
}

fn is_encounter_end(line: []const u8) bool {
    const event_start = find_double_space(line) orelse return false;
    const rest = line[event_start..];
    return std.mem.startsWith(u8, rest, "ENCOUNTER_END,");
}

fn is_challenge_mode_start(line: []const u8) bool {
    const event_start = find_double_space(line) orelse return false;
    const rest = line[event_start..];
    return std.mem.startsWith(u8, rest, "CHALLENGE_MODE_START,");
}

fn is_challenge_mode_end(line: []const u8) bool {
    const event_start = find_double_space(line) orelse return false;
    const rest = line[event_start..];
    return std.mem.startsWith(u8, rest, "CHALLENGE_MODE_END,");
}

fn find_double_space(line: []const u8) ?usize {
    var i: usize = 0;
    while (i + 1 < line.len) : (i += 1) {
        if (line[i] == ' ' and line[i + 1] == ' ') {
            return i + 2;
        }
    }
    return null;
}

// =========================================================================
// ENCOUNTER_START parsing
// =========================================================================

fn parse_encounter_start_fields(line: []const u8, enc_id: *[64]u8, enc_id_len: *usize, name: *[256]u8, name_len: *usize, difficulty_id: *i32, group_size: *i32, instance_id: *[64]u8, instance_id_len: *usize, start_ts: *[64]u8, start_ts_len: *usize) void {
    // Extract timestamp (everything before double-space)
    const event_start = find_double_space(line) orelse return;
    const ts = line[0 .. event_start - 2];
    const ts_copy_len = @min(ts.len, 64);
    @memcpy(start_ts[0..ts_copy_len], ts[0..ts_copy_len]);
    start_ts_len.* = ts_copy_len;

    // Parse CSV fields after "ENCOUNTER_START,"
    const rest = line[event_start + 16 ..]; // skip "ENCOUNTER_START,"
    var field_idx: u32 = 0;
    var pos: usize = 0;

    while (pos < rest.len and field_idx < 5) {
        const field = next_csv_field(rest, &pos);

        switch (field_idx) {
            0 => { // encounter_id
                const copy_len = @min(field.len, 64);
                @memcpy(enc_id[0..copy_len], field[0..copy_len]);
                enc_id_len.* = copy_len;
            },
            1 => { // name (may be quoted)
                const unquoted = unquote(field);
                const copy_len = @min(unquoted.len, 256);
                @memcpy(name[0..copy_len], unquoted[0..copy_len]);
                name_len.* = copy_len;
            },
            2 => { // difficulty_id
                difficulty_id.* = parse_int_field(field);
            },
            3 => { // group_size
                group_size.* = parse_int_field(field);
            },
            4 => { // instance_id
                const copy_len = @min(field.len, 64);
                @memcpy(instance_id[0..copy_len], field[0..copy_len]);
                instance_id_len.* = copy_len;
            },
            else => {},
        }
        field_idx += 1;
    }
}

// =========================================================================
// ENCOUNTER_END parsing
// =========================================================================

fn parse_encounter_end_fields(line: []const u8, success: *bool, fight_time_ms: *i64, end_ts: *[64]u8, end_ts_len: *usize) void {
    // Extract timestamp
    const event_start = find_double_space(line) orelse return;
    const ts = line[0 .. event_start - 2];
    const ts_copy_len = @min(ts.len, 64);
    @memcpy(end_ts[0..ts_copy_len], ts[0..ts_copy_len]);
    end_ts_len.* = ts_copy_len;

    // Parse CSV fields after "ENCOUNTER_END,"
    const rest = line[event_start + 14 ..]; // skip "ENCOUNTER_END,"
    var field_idx: u32 = 0;
    var pos: usize = 0;

    while (pos < rest.len and field_idx < 7) {
        const field = next_csv_field(rest, &pos);

        switch (field_idx) {
            // 0=encounter_id, 1=name, 2=difficulty_id, 3=group_size (skip)
            4 => { // success
                success.* = field.len == 1 and field[0] == '1';
            },
            5 => { // fight_time_ms
                fight_time_ms.* = parse_i64_field(field);
            },
            else => {},
        }
        field_idx += 1;
    }
}

// =========================================================================
// Event line parsing
// =========================================================================

fn parse_event_line(env: *e.ErlNifEnv, line: []const u8, encounter_start_us: i128) ?beam.term {
    const event_start = find_double_space(line) orelse return null;
    const ts_str = line[0 .. event_start - 2];
    const rest = line[event_start..];

    // Get event type (first CSV field)
    var pos: usize = 0;
    const event_type_field = next_csv_field(rest, &pos);

    // Parse timestamp
    const ts_us = parse_timestamp_to_us(ts_str) orelse return null;
    const time_into_fight_us = ts_us - encounter_start_us;
    const time_into_fight: f64 = @as(f64, @floatFromInt(time_into_fight_us)) / 1_000_000.0;

    // Build the event map based on type
    // Common: type, timestamp string, time_into_fight
    const type_term = make_binary_term(env, event_type_field);
    const ts_term = make_binary_term(env, ts_str);
    const tif_term = beam.make(time_into_fight, .{});

    // Parse common prefix fields (source/target) for most events
    // Fields after event_type: source_guid, source_name, source_flags, source_raid_flags,
    //                          target_guid, target_name, target_flags, target_raid_flags

    // Skip meta events (boundaries are handled by scan_boundaries)
    if (std.mem.eql(u8, event_type_field, "COMBAT_LOG_VERSION") or
        std.mem.eql(u8, event_type_field, "ENCOUNTER_START") or
        std.mem.eql(u8, event_type_field, "ENCOUNTER_END") or
        std.mem.eql(u8, event_type_field, "CHALLENGE_MODE_START") or
        std.mem.eql(u8, event_type_field, "CHALLENGE_MODE_END"))
    {
        return null;
    }

    // Zone/map events: emit as lightweight events (type + timestamp only)
    if (std.mem.eql(u8, event_type_field, "ZONE_CHANGE") or
        std.mem.eql(u8, event_type_field, "MAP_CHANGE"))
    {
        var zone_keys: [3]e.ErlNifTerm = undefined;
        var zone_vals: [3]e.ErlNifTerm = undefined;
        zone_keys[0] = e.enif_make_atom(env, "type");
        zone_vals[0] = type_term.v;
        zone_keys[1] = e.enif_make_atom(env, "timestamp");
        zone_vals[1] = ts_term.v;
        zone_keys[2] = e.enif_make_atom(env, "time_into_fight");
        zone_vals[2] = tif_term.v;
        var zone_result: e.ErlNifTerm = undefined;
        _ = e.enif_make_map_from_arrays(env, &zone_keys, &zone_vals, 3, &zone_result);
        return .{ .v = zone_result };
    }

    // For COMBATANT_INFO, handle specially (different field layout)
    if (std.mem.eql(u8, event_type_field, "COMBATANT_INFO")) {
        return parse_combatant_info(env, rest, type_term, ts_term, tif_term);
    }

    // Parse common prefix (8 fields after event_type)
    var source_guid: []const u8 = "";
    var source_name: []const u8 = "";
    var source_flags: i64 = 0;
    var target_guid: []const u8 = "";
    var target_name: []const u8 = "";
    var target_flags: i64 = 0;

    // Field 1: source_guid
    source_guid = unquote(next_csv_field(rest, &pos));
    // Field 2: source_name
    source_name = unquote(next_csv_field(rest, &pos));
    // Field 3: source_flags (hex)
    source_flags = parse_hex_field(next_csv_field(rest, &pos));
    // Field 4: source_raid_flags (skip)
    _ = next_csv_field(rest, &pos);
    // Field 5: target_guid
    target_guid = unquote(next_csv_field(rest, &pos));
    // Field 6: target_name
    target_name = unquote(next_csv_field(rest, &pos));
    // Field 7: target_flags (hex)
    target_flags = parse_hex_field(next_csv_field(rest, &pos));
    // Field 8: target_raid_flags (skip)
    _ = next_csv_field(rest, &pos);

    // Build base keys/vals arrays
    var keys: [20]e.ErlNifTerm = undefined;
    var vals: [20]e.ErlNifTerm = undefined;
    var field_count: u32 = 0;

    // Always present fields
    keys[field_count] = e.enif_make_atom(env, "type");
    vals[field_count] = type_term.v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "timestamp");
    vals[field_count] = ts_term.v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "time_into_fight");
    vals[field_count] = tif_term.v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "source_guid");
    vals[field_count] = make_binary_term(env, source_guid).v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "source_name");
    vals[field_count] = make_binary_term(env, source_name).v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "source_flags");
    vals[field_count] = beam.make(source_flags, .{}).v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "target_guid");
    vals[field_count] = make_binary_term(env, target_guid).v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "target_name");
    vals[field_count] = make_binary_term(env, target_name).v;
    field_count += 1;

    keys[field_count] = e.enif_make_atom(env, "target_flags");
    vals[field_count] = beam.make(target_flags, .{}).v;
    field_count += 1;

    // Event-type-specific fields
    if (std.mem.eql(u8, event_type_field, "UNIT_DIED")) {
        // UNIT_DIED has no additional fields we need beyond the prefix
        // (the extra field after prefix is just "0")
    } else if (std.mem.eql(u8, event_type_field, "SWING_DAMAGE")) {
        // SWING_DAMAGE: no spell info, but has advanced params
        // Skip to the advanced combat log params
        // After prefix (8 fields), the next fields are the advanced info block
        // For SWING_DAMAGE, damage amount is at specific positions in advanced params
        parse_swing_damage_fields(env, rest, &pos, &keys, &vals, &field_count);
    } else if (has_spell_prefix(event_type_field)) {
        // Events with spell prefix: spell_id, spell_name, spell_school
        const spell_id_str = next_csv_field(rest, &pos);
        const spell_name_raw = next_csv_field(rest, &pos);
        const spell_school_str = next_csv_field(rest, &pos);

        keys[field_count] = e.enif_make_atom(env, "spell_id");
        vals[field_count] = beam.make(parse_i64_field(spell_id_str), .{}).v;
        field_count += 1;

        keys[field_count] = e.enif_make_atom(env, "spell_name");
        vals[field_count] = make_binary_term(env, unquote(spell_name_raw)).v;
        field_count += 1;

        keys[field_count] = e.enif_make_atom(env, "spell_school");
        vals[field_count] = beam.make(parse_hex_or_int_field(spell_school_str), .{}).v;
        field_count += 1;

        // Handle damage suffix events
        if (std.mem.eql(u8, event_type_field, "SPELL_DAMAGE") or
            std.mem.eql(u8, event_type_field, "SPELL_PERIODIC_DAMAGE") or
            std.mem.eql(u8, event_type_field, "RANGE_DAMAGE"))
        {
            parse_spell_damage_fields(env, rest, &pos, &keys, &vals, &field_count);
        } else if (std.mem.eql(u8, event_type_field, "SPELL_HEAL") or
            std.mem.eql(u8, event_type_field, "SPELL_PERIODIC_HEAL"))
        {
            parse_heal_fields(env, rest, &pos, &keys, &vals, &field_count);
        } else if (std.mem.eql(u8, event_type_field, "SPELL_INTERRUPT")) {
            // Extra spell info: the spell that was interrupted
            const extra_spell_id_str = next_csv_field(rest, &pos);
            const extra_spell_name_raw = next_csv_field(rest, &pos);

            keys[field_count] = e.enif_make_atom(env, "extra_spell_id");
            vals[field_count] = beam.make(parse_i64_field(extra_spell_id_str), .{}).v;
            field_count += 1;

            keys[field_count] = e.enif_make_atom(env, "extra_spell_name");
            vals[field_count] = make_binary_term(env, unquote(extra_spell_name_raw)).v;
            field_count += 1;
        } else if (std.mem.eql(u8, event_type_field, "SPELL_AURA_APPLIED") or
            std.mem.eql(u8, event_type_field, "SPELL_AURA_REMOVED") or
            std.mem.eql(u8, event_type_field, "SPELL_AURA_APPLIED_DOSE") or
            std.mem.eql(u8, event_type_field, "SPELL_AURA_REMOVED_DOSE"))
        {
            // Next field is aura type (BUFF/DEBUFF)
            const aura_type_field = next_csv_field(rest, &pos);
            const aura_type = unquote(aura_type_field);

            // Build extra map with aura_type
            var extra_keys = [_]e.ErlNifTerm{e.enif_make_atom(env, "aura_type")};
            var extra_vals = [_]e.ErlNifTerm{make_binary_term(env, aura_type).v};
            var extra_map: e.ErlNifTerm = undefined;
            _ = e.enif_make_map_from_arrays(env, &extra_keys, &extra_vals, 1, &extra_map);

            keys[field_count] = e.enif_make_atom(env, "extra");
            vals[field_count] = extra_map;
            field_count += 1;
        }
    } else if (std.mem.eql(u8, event_type_field, "ENVIRONMENTAL_DAMAGE")) {
        // ENVIRONMENTAL_DAMAGE has env type then damage info
        const env_type_field = next_csv_field(rest, &pos);
        const env_type = unquote(env_type_field);

        keys[field_count] = e.enif_make_atom(env, "spell_name");
        vals[field_count] = make_binary_term(env, env_type).v;
        field_count += 1;

        keys[field_count] = e.enif_make_atom(env, "spell_id");
        vals[field_count] = beam.make(@as(i64, 0), .{}).v;
        field_count += 1;

        keys[field_count] = e.enif_make_atom(env, "spell_school");
        vals[field_count] = beam.make(@as(i64, 1), .{}).v;
        field_count += 1;

        parse_env_damage_fields(env, rest, &pos, &keys, &vals, &field_count);
    }

    var result: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &keys, &vals, field_count, &result);
    return .{ .v = result };
}

fn parse_combatant_info(env: *e.ErlNifEnv, rest: []const u8, type_term: beam.term, ts_term: beam.term, tif_term: beam.term) ?beam.term {
    var pos: usize = 0;
    // Skip "COMBATANT_INFO,"
    _ = next_csv_field(rest, &pos); // event type already parsed

    // Field 1: player GUID
    const player_guid = unquote(next_csv_field(rest, &pos));

    // Skip to spec_id - it's at a known position in the field list
    // COMBATANT_INFO has many fields, spec_id is at position 24 (0-indexed from after GUID)
    var field_idx: u32 = 0;
    var spec_id: i64 = 0;
    while (field_idx < 23 and pos < rest.len) : (field_idx += 1) {
        _ = next_csv_field(rest, &pos);
    }
    if (pos < rest.len) {
        spec_id = parse_i64_field(next_csv_field(rest, &pos));
    }

    // Build extra map with spec_id
    var extra_keys = [_]e.ErlNifTerm{e.enif_make_atom(env, "spec_id")};
    var extra_vals = [_]e.ErlNifTerm{beam.make(spec_id, .{}).v};
    var extra_map: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &extra_keys, &extra_vals, 1, &extra_map);

    var keys: [5]e.ErlNifTerm = undefined;
    var vals: [5]e.ErlNifTerm = undefined;

    keys[0] = e.enif_make_atom(env, "type");
    vals[0] = type_term.v;
    keys[1] = e.enif_make_atom(env, "timestamp");
    vals[1] = ts_term.v;
    keys[2] = e.enif_make_atom(env, "time_into_fight");
    vals[2] = tif_term.v;
    keys[3] = e.enif_make_atom(env, "source_guid");
    vals[3] = make_binary_term(env, player_guid).v;
    keys[4] = e.enif_make_atom(env, "extra");
    vals[4] = extra_map;

    var result: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &keys, &vals, 5, &result);
    return .{ .v = result };
}

fn has_spell_prefix(event_type: []const u8) bool {
    return std.mem.startsWith(u8, event_type, "SPELL_") or
        std.mem.startsWith(u8, event_type, "RANGE_");
}

fn parse_swing_damage_fields(env: *e.ErlNifEnv, rest: []const u8, pos: *usize, keys: *[20]e.ErlNifTerm, vals: *[20]e.ErlNifTerm, field_count: *u32) void {
    // SWING_DAMAGE with advanced combat logging:
    // After the 8-field common prefix, there's the advanced info block
    // (informational GUID, owner GUID, current HP, max HP, ... 13 fields)
    // Then: amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand
    // Skip advanced info (about 13 fields: info_guid, owner_guid, hp, maxhp, attackpower, spellpower, armor, absorb, ...)

    // Set spell_name to "Melee" for swing damage
    keys[field_count.*] = e.enif_make_atom(env, "spell_name");
    vals[field_count.*] = make_binary_term(env, "Melee").v;
    field_count.* += 1;

    keys[field_count.*] = e.enif_make_atom(env, "spell_id");
    vals[field_count.*] = beam.make(@as(i64, 0), .{}).v;
    field_count.* += 1;

    keys[field_count.*] = e.enif_make_atom(env, "spell_school");
    vals[field_count.*] = beam.make(@as(i64, 1), .{}).v; // physical
    field_count.* += 1;

    // Skip 19 advanced info fields (TWW/12.0 format)
    var skip: u32 = 0;
    while (skip < 19 and pos.* < rest.len) : (skip += 1) {
        _ = next_csv_field(rest, pos);
    }

    // amount
    const amount_str = next_csv_field(rest, pos);
    const amount = parse_i64_field(amount_str);
    keys[field_count.*] = e.enif_make_atom(env, "amount");
    vals[field_count.*] = beam.make(amount, .{}).v;
    field_count.* += 1;

    // overkill
    const overkill_str = next_csv_field(rest, pos);
    var overkill = parse_i64_field(overkill_str);
    if (overkill < 0) overkill = 0;
    keys[field_count.*] = e.enif_make_atom(env, "overkill");
    vals[field_count.*] = beam.make(overkill, .{}).v;
    field_count.* += 1;

    // skip school
    _ = next_csv_field(rest, pos);
    // skip resisted
    _ = next_csv_field(rest, pos);
    // skip blocked
    _ = next_csv_field(rest, pos);

    // absorbed
    const absorbed_str = next_csv_field(rest, pos);
    const absorbed = parse_i64_field(absorbed_str);
    keys[field_count.*] = e.enif_make_atom(env, "absorbed");
    vals[field_count.*] = beam.make(absorbed, .{}).v;
    field_count.* += 1;
}

fn parse_spell_damage_fields(env: *e.ErlNifEnv, rest: []const u8, pos: *usize, keys: *[20]e.ErlNifTerm, vals: *[20]e.ErlNifTerm, field_count: *u32) void {
    // After spell prefix (spell_id, spell_name, spell_school), same advanced info block
    // Skip 19 advanced info fields (TWW/12.0 format)
    var skip: u32 = 0;
    while (skip < 19 and pos.* < rest.len) : (skip += 1) {
        _ = next_csv_field(rest, pos);
    }

    // amount
    const amount_str = next_csv_field(rest, pos);
    const amount = parse_i64_field(amount_str);
    keys[field_count.*] = e.enif_make_atom(env, "amount");
    vals[field_count.*] = beam.make(amount, .{}).v;
    field_count.* += 1;

    // overkill
    const overkill_str = next_csv_field(rest, pos);
    var overkill = parse_i64_field(overkill_str);
    if (overkill < 0) overkill = 0;
    keys[field_count.*] = e.enif_make_atom(env, "overkill");
    vals[field_count.*] = beam.make(overkill, .{}).v;
    field_count.* += 1;

    // skip school
    _ = next_csv_field(rest, pos);
    // skip resisted
    _ = next_csv_field(rest, pos);
    // skip blocked
    _ = next_csv_field(rest, pos);

    // absorbed
    const absorbed_str = next_csv_field(rest, pos);
    const absorbed = parse_i64_field(absorbed_str);
    keys[field_count.*] = e.enif_make_atom(env, "absorbed");
    vals[field_count.*] = beam.make(absorbed, .{}).v;
    field_count.* += 1;
}

fn parse_heal_fields(env: *e.ErlNifEnv, rest: []const u8, pos: *usize, keys: *[20]e.ErlNifTerm, vals: *[20]e.ErlNifTerm, field_count: *u32) void {
    // After spell prefix, skip advanced info (13 fields)
    var skip: u32 = 0;
    while (skip < 13 and pos.* < rest.len) : (skip += 1) {
        _ = next_csv_field(rest, pos);
    }

    // amount
    const amount_str = next_csv_field(rest, pos);
    const amount = parse_i64_field(amount_str);
    keys[field_count.*] = e.enif_make_atom(env, "amount");
    vals[field_count.*] = beam.make(amount, .{}).v;
    field_count.* += 1;

    // overhealing
    const overheal_str = next_csv_field(rest, pos);
    const overheal = parse_i64_field(overheal_str);
    keys[field_count.*] = e.enif_make_atom(env, "overkill");
    vals[field_count.*] = beam.make(overheal, .{}).v;
    field_count.* += 1;

    // absorbed
    const absorbed_str = next_csv_field(rest, pos);
    const absorbed = parse_i64_field(absorbed_str);
    keys[field_count.*] = e.enif_make_atom(env, "absorbed");
    vals[field_count.*] = beam.make(absorbed, .{}).v;
    field_count.* += 1;
}

fn parse_env_damage_fields(env: *e.ErlNifEnv, rest: []const u8, pos: *usize, keys: *[20]e.ErlNifTerm, vals: *[20]e.ErlNifTerm, field_count: *u32) void {
    // Environmental damage: after env_type, has advanced info + damage
    // Skip 19 advanced info fields (TWW/12.0 format)
    var skip: u32 = 0;
    while (skip < 19 and pos.* < rest.len) : (skip += 1) {
        _ = next_csv_field(rest, pos);
    }

    const amount_str = next_csv_field(rest, pos);
    const amount = parse_i64_field(amount_str);
    keys[field_count.*] = e.enif_make_atom(env, "amount");
    vals[field_count.*] = beam.make(amount, .{}).v;
    field_count.* += 1;

    const overkill_str = next_csv_field(rest, pos);
    var overkill = parse_i64_field(overkill_str);
    if (overkill < 0) overkill = 0;
    keys[field_count.*] = e.enif_make_atom(env, "overkill");
    vals[field_count.*] = beam.make(overkill, .{}).v;
    field_count.* += 1;
}

// =========================================================================
// CSV field parsing helpers
// =========================================================================

fn next_csv_field(data: []const u8, pos: *usize) []const u8 {
    if (pos.* >= data.len) return "";

    const start = pos.*;
    var in_quotes = false;
    var in_brackets = false;
    var depth: u32 = 0;

    while (pos.* < data.len) {
        const c = data[pos.*];
        if (c == '"') {
            in_quotes = !in_quotes;
        } else if (!in_quotes) {
            if (c == '[' or c == '(') {
                in_brackets = true;
                depth += 1;
            } else if ((c == ']' or c == ')') and depth > 0) {
                depth -= 1;
                if (depth == 0) in_brackets = false;
            } else if (c == ',' and !in_brackets) {
                const field = data[start..pos.*];
                pos.* += 1; // skip comma
                return field;
            }
        }
        pos.* += 1;
    }

    return data[start..pos.*];
}

fn unquote(field: []const u8) []const u8 {
    if (field.len >= 2 and field[0] == '"' and field[field.len - 1] == '"') {
        return field[1 .. field.len - 1];
    }
    return field;
}

fn parse_int_field(field: []const u8) i32 {
    if (field.len == 0) return 0;
    return std.fmt.parseInt(i32, field, 10) catch 0;
}

fn parse_i64_field(field: []const u8) i64 {
    if (field.len == 0) return 0;
    // Handle "nil" values
    if (std.mem.eql(u8, field, "nil")) return 0;
    return std.fmt.parseInt(i64, field, 10) catch 0;
}

fn parse_hex_field(field: []const u8) i64 {
    if (field.len == 0) return 0;
    // Handle "0x" prefix
    if (field.len > 2 and field[0] == '0' and field[1] == 'x') {
        return std.fmt.parseInt(i64, field[2..], 16) catch 0;
    }
    return std.fmt.parseInt(i64, field, 16) catch 0;
}

fn parse_hex_or_int_field(field: []const u8) i64 {
    if (field.len == 0) return 0;
    if (field.len > 2 and field[0] == '0' and field[1] == 'x') {
        return parse_hex_field(field);
    }
    return parse_i64_field(field);
}

// =========================================================================
// Timestamp parsing
// =========================================================================

fn parse_timestamp_to_us(ts: []const u8) ?i128 {
    // Format: "M/DD/YYYY HH:MM:SS.mmm-TZ" or "MM/DD/YYYY HH:MM:SS.mmm-TZ"
    // We ignore timezone offset

    // Find the space between date and time
    var space_idx: usize = 0;
    for (ts, 0..) |c, i| {
        if (c == ' ') {
            space_idx = i;
            break;
        }
    }
    if (space_idx == 0) return null;

    const date_part = ts[0..space_idx];
    var time_part = ts[space_idx + 1 ..];

    // Strip timezone (everything after and including the last '-' or '+')
    // But be careful: the '-' in timezone comes after the milliseconds
    // Find the dot first, then the tz separator after it
    var dot_idx: usize = 0;
    for (time_part, 0..) |c, i| {
        if (c == '.') {
            dot_idx = i;
            break;
        }
    }

    var ms_end = time_part.len;
    if (dot_idx > 0) {
        var j = dot_idx + 1;
        while (j < time_part.len) : (j += 1) {
            if (time_part[j] == '-' or time_part[j] == '+') {
                ms_end = j;
                break;
            }
        }
    }
    time_part = time_part[0..ms_end];

    // Parse date: M/DD/YYYY
    var date_pos: usize = 0;
    const month = parse_next_int(date_part, &date_pos, '/') orelse return null;
    const day = parse_next_int(date_part, &date_pos, '/') orelse return null;
    const year = parse_next_int(date_part, &date_pos, 0) orelse return null;

    // Parse time: HH:MM:SS.mmm
    var time_pos: usize = 0;
    const hour = parse_next_int(time_part, &time_pos, ':') orelse return null;
    const minute = parse_next_int(time_part, &time_pos, ':') orelse return null;
    const second = parse_next_int(time_part, &time_pos, '.') orelse return null;
    const ms = if (dot_idx > 0) (parse_next_int(time_part, &time_pos, 0) orelse 0) else 0;

    // Convert to microseconds since epoch (simplified: just relative value works for time_into_fight)
    const days = days_since_epoch(@intCast(year), @intCast(month), @intCast(day));
    const total_us: i128 = @as(i128, days) * 86400 * 1_000_000 +
        @as(i128, hour) * 3600 * 1_000_000 +
        @as(i128, minute) * 60 * 1_000_000 +
        @as(i128, second) * 1_000_000 +
        @as(i128, ms) * 1_000;

    return total_us;
}

fn parse_next_int(data: []const u8, pos: *usize, delimiter: u8) ?i64 {
    if (pos.* >= data.len) return null;
    const start = pos.*;
    while (pos.* < data.len and data[pos.*] != delimiter) : (pos.* += 1) {}
    const field = data[start..pos.*];
    if (pos.* < data.len) pos.* += 1; // skip delimiter
    return std.fmt.parseInt(i64, field, 10) catch null;
}

fn days_since_epoch(year: i32, month: i32, day: i32) i64 {
    // Simple days-since-epoch calculation
    var y = year;
    var m = month;
    if (m <= 2) {
        y -= 1;
        m += 12;
    }
    const era_y: i64 = @intCast(y);
    const era_m: i64 = @intCast(m);
    const era_d: i64 = @intCast(day);
    return 365 * era_y + @divFloor(era_y, 4) - @divFloor(era_y, 100) + @divFloor(era_y, 400) + @divFloor((153 * (era_m - 3) + 2), 5) + era_d - 719469;
}

// =========================================================================
// Helpers
// =========================================================================

fn skip_to_line_boundary(file: std.fs.File) !void {
    var buf: [1]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) return; // EOF
        if (buf[0] == '\n') return;
    }
}

fn make_error_tuple(env: *e.ErlNifEnv, reason: []const u8) beam.term {
    const error_atom = e.enif_make_atom(env, "error");
    const reason_atom = e.enif_make_atom(env, reason.ptr);
    return .{ .v = e.enif_make_tuple2(env, error_atom, reason_atom) };
}

fn make_binary_term(env: *e.ErlNifEnv, data: []const u8) beam.term {
    var result: e.ErlNifTerm = undefined;
    const buf = e.enif_make_new_binary(env, data.len, &result);
    if (buf != null) {
        @memcpy(buf[0..data.len], data);
    }
    return .{ .v = result };
}

// =========================================================================
// CHALLENGE_MODE_START parsing
// Format: CHALLENGE_MODE_START,"zoneName",instanceID,challengeModeID,keystoneLevel,[affixID,...]
// =========================================================================

fn parse_challenge_mode_start_fields(line: []const u8, name: *[256]u8, name_len: *usize, instance_id: *[64]u8, instance_id_len: *usize, challenge_mode_id: *i32, keystone_level: *i32, start_ts: *[64]u8, start_ts_len: *usize) void {
    const event_start = find_double_space(line) orelse return;
    const ts = line[0 .. event_start - 2];
    const ts_copy_len = @min(ts.len, 64);
    @memcpy(start_ts[0..ts_copy_len], ts[0..ts_copy_len]);
    start_ts_len.* = ts_copy_len;

    // Skip "CHALLENGE_MODE_START,"
    const rest = line[event_start + 21 ..];
    var field_idx: u32 = 0;
    var pos: usize = 0;

    while (pos < rest.len and field_idx < 5) {
        const field = next_csv_field(rest, &pos);

        switch (field_idx) {
            0 => { // zoneName (quoted)
                const unquoted = unquote(field);
                const copy_len = @min(unquoted.len, 256);
                @memcpy(name[0..copy_len], unquoted[0..copy_len]);
                name_len.* = copy_len;
            },
            1 => { // instanceID
                const copy_len = @min(field.len, 64);
                @memcpy(instance_id[0..copy_len], field[0..copy_len]);
                instance_id_len.* = copy_len;
            },
            2 => { // challengeModeID
                challenge_mode_id.* = parse_int_field(field);
            },
            3 => { // keystoneLevel
                keystone_level.* = parse_int_field(field);
            },
            else => {},
        }
        field_idx += 1;
    }
}

// =========================================================================
// CHALLENGE_MODE_END parsing
// Format: CHALLENGE_MODE_END,instanceID,success,keystoneLevel,totalTime
// =========================================================================

fn parse_challenge_mode_end_fields(line: []const u8, success: *bool, keystone_level: *i32, total_time_ms: *i64, end_ts: *[64]u8, end_ts_len: *usize) void {
    const event_start = find_double_space(line) orelse return;
    const ts = line[0 .. event_start - 2];
    const ts_copy_len = @min(ts.len, 64);
    @memcpy(end_ts[0..ts_copy_len], ts[0..ts_copy_len]);
    end_ts_len.* = ts_copy_len;

    // Skip "CHALLENGE_MODE_END,"
    const rest = line[event_start + 19 ..];
    var field_idx: u32 = 0;
    var pos: usize = 0;

    while (pos < rest.len and field_idx < 5) {
        const field = next_csv_field(rest, &pos);

        switch (field_idx) {
            // 0 = instanceID (skip, we have it from start)
            1 => { // success
                success.* = field.len == 1 and field[0] == '1';
            },
            2 => { // keystoneLevel
                keystone_level.* = parse_int_field(field);
            },
            3 => { // totalTime (ms)
                total_time_ms.* = parse_i64_field(field);
            },
            else => {},
        }
        field_idx += 1;
    }
}

fn make_challenge_mode_start_map(env: *e.ErlNifEnv, name: []const u8, instance_id: []const u8, challenge_mode_id: i32, keystone_level: i32, byte_pos: u64, start_ts: []const u8) beam.term {
    var keys: [7]e.ErlNifTerm = undefined;
    var vals: [7]e.ErlNifTerm = undefined;

    keys[0] = e.enif_make_atom(env, "boundary_type");
    vals[0] = e.enif_make_atom(env, "challenge_mode_start");

    keys[1] = e.enif_make_atom(env, "name");
    vals[1] = make_binary_term(env, name).v;

    keys[2] = e.enif_make_atom(env, "instance_id");
    vals[2] = make_binary_term(env, instance_id).v;

    keys[3] = e.enif_make_atom(env, "challenge_mode_id");
    vals[3] = beam.make(@as(i64, challenge_mode_id), .{}).v;

    keys[4] = e.enif_make_atom(env, "keystone_level");
    vals[4] = beam.make(@as(i64, keystone_level), .{}).v;

    keys[5] = e.enif_make_atom(env, "start_byte");
    vals[5] = beam.make(byte_pos, .{}).v;

    keys[6] = e.enif_make_atom(env, "start_timestamp");
    vals[6] = make_binary_term(env, start_ts).v;

    var result: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &keys, &vals, 7, &result);
    return .{ .v = result };
}

fn make_challenge_mode_end_map(env: *e.ErlNifEnv, success: bool, keystone_level: i32, total_time_ms: i64, byte_pos: u64, end_ts: []const u8) beam.term {
    var keys: [6]e.ErlNifTerm = undefined;
    var vals: [6]e.ErlNifTerm = undefined;

    keys[0] = e.enif_make_atom(env, "boundary_type");
    vals[0] = e.enif_make_atom(env, "challenge_mode_end");

    keys[1] = e.enif_make_atom(env, "success");
    vals[1] = beam.make(success, .{}).v;

    keys[2] = e.enif_make_atom(env, "keystone_level");
    vals[2] = beam.make(@as(i64, keystone_level), .{}).v;

    keys[3] = e.enif_make_atom(env, "total_time_ms");
    vals[3] = beam.make(total_time_ms, .{}).v;

    keys[4] = e.enif_make_atom(env, "end_byte");
    vals[4] = beam.make(byte_pos, .{}).v;

    keys[5] = e.enif_make_atom(env, "end_timestamp");
    vals[5] = make_binary_term(env, end_ts).v;

    var result: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &keys, &vals, 6, &result);
    return .{ .v = result };
}

fn make_boundary_map(env: *e.ErlNifEnv, encounter_id: []const u8, name: []const u8, difficulty_id: i32, group_size: i32, instance_id: []const u8, start_byte: u64, end_byte: u64, start_ts: []const u8, end_ts: []const u8, success: bool, fight_time_ms: i64) beam.term {
    var keys: [12]e.ErlNifTerm = undefined;
    var vals: [12]e.ErlNifTerm = undefined;

    keys[0] = e.enif_make_atom(env, "boundary_type");
    vals[0] = e.enif_make_atom(env, "encounter");

    keys[1] = e.enif_make_atom(env, "wow_encounter_id");
    vals[1] = make_binary_term(env, encounter_id).v;

    keys[2] = e.enif_make_atom(env, "name");
    vals[2] = make_binary_term(env, name).v;

    keys[3] = e.enif_make_atom(env, "difficulty_id");
    vals[3] = beam.make(@as(i64, difficulty_id), .{}).v;

    keys[4] = e.enif_make_atom(env, "group_size");
    vals[4] = beam.make(@as(i64, group_size), .{}).v;

    keys[5] = e.enif_make_atom(env, "instance_id");
    vals[5] = make_binary_term(env, instance_id).v;

    keys[6] = e.enif_make_atom(env, "start_byte");
    vals[6] = beam.make(start_byte, .{}).v;

    keys[7] = e.enif_make_atom(env, "end_byte");
    vals[7] = beam.make(end_byte, .{}).v;

    keys[8] = e.enif_make_atom(env, "start_timestamp");
    vals[8] = make_binary_term(env, start_ts).v;

    keys[9] = e.enif_make_atom(env, "end_timestamp");
    vals[9] = make_binary_term(env, end_ts).v;

    keys[10] = e.enif_make_atom(env, "success");
    vals[10] = beam.make(success, .{}).v;

    keys[11] = e.enif_make_atom(env, "fight_time_ms");
    vals[11] = beam.make(fight_time_ms, .{}).v;

    var result: e.ErlNifTerm = undefined;
    _ = e.enif_make_map_from_arrays(env, &keys, &vals, 12, &result);
    return .{ .v = result };
}
