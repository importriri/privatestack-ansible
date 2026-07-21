#!/usr/bin/env bats
# Protocol tests for the gpu_handoff qemu hook. The hook is invoked
# DIRECTLY (not via bash): the executable bit is part of the contract.

setup() {
    TESTDIR="$(mktemp -d)"
    export GPU_HANDOFF_ROTATION="${TESTDIR}/rotation"
    export GPU_HANDOFF_STATE_DIR="${TESTDIR}/state"
    HOOK="${BATS_TEST_DIRNAME}/../roles/gpu_handoff/files/qemu"
    cat > "${GPU_HANDOFF_ROTATION}" <<EOF
# domain trust
clean 3
dev 2
dirty 1
lab 0
EOF
}

teardown() {
    rm -rf "${TESTDIR}"
}

state() {
    cat "${GPU_HANDOFF_STATE_DIR}/trust"
}

@test "the hook file itself carries the executable bit (the 100644 trap)" {
    [ -x "${HOOK}" ]
}

@test "first GPU domain is allowed and records its trust" {
    run "${HOOK}" clean prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "3" ]
}

@test "downgrade is allowed (clean -> dirty)" {
    "${HOOK}" clean prepare
    run "${HOOK}" dirty prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "1" ]
}

@test "lateral restart at the same trust is allowed" {
    "${HOOK}" dirty prepare
    run "${HOOK}" dirty prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "1" ]
}

@test "upgrade is refused and leaves state untouched (dirty -> clean)" {
    "${HOOK}" dirty prepare
    run "${HOOK}" clean prepare
    [ "$status" -eq 1 ]
    [[ "$output" == *REFUSING* ]]
    [ "$(state)" = "1" ]
}

@test "lab can start first" {
    run "${HOOK}" lab prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "0" ]
}

@test "after lab, every GPU domain is refused until reboot" {
    "${HOOK}" lab prepare
    run "${HOOK}" dirty prepare
    [ "$status" -eq 1 ]
}

@test "a reboot (state dir gone) reopens the ladder" {
    "${HOOK}" lab prepare
    rm -rf "${GPU_HANDOFF_STATE_DIR}"
    run "${HOOK}" clean prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "3" ]
}

@test "corrupt state refuses GPU domains (fail closed)" {
    mkdir -p "${GPU_HANDOFF_STATE_DIR}"
    echo garbage > "${GPU_HANDOFF_STATE_DIR}/trust"
    run "${HOOK}" clean prepare
    [ "$status" -eq 1 ]
}

@test "corrupt rotation refuses even unlisted domains (fail closed)" {
    echo "clean banana" > "${GPU_HANDOFF_ROTATION}"
    run "${HOOK}" svc-jellyfin prepare
    [ "$status" -eq 1 ]
}

@test "missing rotation refuses (fail closed)" {
    rm -f "${GPU_HANDOFF_ROTATION}"
    run "${HOOK}" clean prepare
    [ "$status" -eq 1 ]
}

@test "empty rotation is a broken config, not a disabled handoff" {
    : > "${GPU_HANDOFF_ROTATION}"
    run "${HOOK}" svc-jellyfin prepare
    [ "$status" -eq 1 ]
}

@test "a service domain passes while the GPU is held, state untouched" {
    "${HOOK}" clean prepare
    run "${HOOK}" svc-jellyfin prepare
    [ "$status" -eq 0 ]
    [ "$(state)" = "3" ]
}

@test "a service domain passes with no state and creates none" {
    run "${HOOK}" svc-jellyfin prepare
    [ "$status" -eq 0 ]
    [ ! -e "${GPU_HANDOFF_STATE_DIR}/trust" ]
}

@test "non-prepare phases pass instantly, even for an upgrade" {
    "${HOOK}" dirty prepare
    run "${HOOK}" clean started
    [ "$status" -eq 0 ]
    [ "$(state)" = "1" ]
}
