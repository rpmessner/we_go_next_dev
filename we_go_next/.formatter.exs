# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs"] ++
      (Path.wildcard("{config,lib,test}/**/*.{ex,exs}") --
         Path.wildcard("lib/we_go_next/game_data/**/*.ex"))
]
