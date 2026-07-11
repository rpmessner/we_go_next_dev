#!/usr/bin/env bash
# Source this file to load we-go-next service credentials from ~/.ssh.
# Secret values stay in the operator-owned files and are never stored here.

_wgn_secret_dir="${HOME}/.ssh"
_wgn_required_files=(
  cloudflare_account_id
  cloudflare_api_token
  cloudflare_s3_api_endpoint
  cloudflare_access_key_id
  cloudflare_secret_access_key
  gigelixir_api_key
  linear_wgn_team_key
)

for _wgn_file in "${_wgn_required_files[@]}"; do
  if [[ ! -s "${_wgn_secret_dir}/${_wgn_file}" ]]; then
    printf 'Missing required secret file: %s\n' "${_wgn_secret_dir}/${_wgn_file}" >&2
    unset _wgn_secret_dir _wgn_required_files _wgn_file
    return 1 2>/dev/null || exit 1
  fi
done

export CLOUDFLARE_ACCOUNT_ID="$(<"${_wgn_secret_dir}/cloudflare_account_id")"
export CLOUDFLARE_API_TOKEN="$(<"${_wgn_secret_dir}/cloudflare_api_token")"
export R2_ENDPOINT="$(<"${_wgn_secret_dir}/cloudflare_s3_api_endpoint")"
export R2_ACCESS_KEY_ID="$(<"${_wgn_secret_dir}/cloudflare_access_key_id")"
export R2_SECRET_ACCESS_KEY="$(<"${_wgn_secret_dir}/cloudflare_secret_access_key")"
export GIGALIXIR_API_KEY="$(<"${_wgn_secret_dir}/gigelixir_api_key")"
export LINEAR_API_KEY="$(<"${_wgn_secret_dir}/linear_wgn_team_key")"

export GIGALIXIR_EMAIL="${GIGALIXIR_EMAIL:-rpmessner@gmail.com}"
export PHX_HOST="${PHX_HOST:-we-go-next.gigalixirapp.com}"
export PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://${PHX_HOST}}"

if [[ -s "${_wgn_secret_dir}/cloudflare_r2_bucket" ]]; then
  export R2_BUCKET="$(<"${_wgn_secret_dir}/cloudflare_r2_bucket")"
elif [[ -z "${R2_BUCKET:-}" ]]; then
  printf '%s\n' \
    'R2_BUCKET is unset. Enable R2, create the bucket, then store its name in ~/.ssh/cloudflare_r2_bucket.' \
    >&2
fi

unset _wgn_secret_dir _wgn_required_files _wgn_file
