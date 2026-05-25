#!/usr/bin/env bats

@test "asterisk lab skeleton files exist" {
  run test -f apps/asterisk-lab/README.md
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/.env.example
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/.gitignore
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/runtime/.gitkeep
  [ "$status" -eq 0 ]
}
