# MUTATIONS.md - the firing range

A test that has never been seen red proves nothing. Every invariant in
this repo earned its place by catching a deliberate breakage before it
was frozen. This is the catalog: for each mutation, the exact command
that breaks the repo, the check that MUST turn red, and the restore.

Replaying one is step 6 of the pre-push ritual:

1. **Predict** which check dies - say it before running anything.
2. Apply the Break command.
3. `./verify.sh` - it must FAIL, where you predicted.
4. Restore. `./verify.sh` - all green again.

Restores assume git (`git checkout -- <file>`, which also restores the
executable bit). Before the first commit, keep a plain copy instead
(`cp <file> /tmp/bak`) - and after restoring the hook that way, re-run
`chmod +x` (the first bats test will remind you if you forget).

All fifteen were executed and caught during the build. Replay at least
one before every push.

## roles/base + the shared contract

### 1. Strict rp_filter
- Break: `sed -i 's/net.ipv4.conf.all.rp_filter = 2/net.ipv4.conf.all.rp_filter = 1/' roles/base/files/99-hardening.conf`
- Red: render suite, "A hardening invariant broke" - five bridges need
  loose mode; strict drops legitimate asymmetric paths.
- Restore: `git checkout -- roles/base/files/99-hardening.conf`

### 2. Broken sudoers drop-in
- Break: `printf '%%wheel ALL=(ALL:ALL NOPASSWD ALL\n' > roles/base/files/10-wheel`
- Red: render suite - the real judge (`visudo -cf`) rejects the file.
- Restore: `git checkout -- roles/base/files/10-wheel`

### 3. services joins the GPU rotation
- Break: `sed -i 's/^  lab: 0$/  lab: 0\n  services: 2/' group_vars/all.yml`
- Red: render suite - contract invariants ("services never joins it").
- Restore: `git checkout -- group_vars/all.yml`

## roles/kvm_host

### 4. qemu-desktop sneaks into the package list
- Break: `sed -i 's/^  - qemu-base$/  - qemu-desktop/' roles/kvm_host/defaults/main.yml`
- Red: render suite - kvm_host invariants. Structural check: the YAML
  is parsed and the actual list inspected, so comments cannot trip it
  (they did once - see the A2 review).
- Restore: `git checkout -- roles/kvm_host/defaults/main.yml`

## roles/vfio_boot

### 5. Backslash continuation in a boot entry
- Break: `sed -i 's|^options zswap.enabled=0$|options zswap.enabled=0 \\|' roles/vfio_boot/templates/entry.conf.j2`
- Red: render suite - boot entry invariants. The Boot Loader Spec has
  no continuations: the loader drops the orphan line silently and the
  machine still boots, missing parameters.
- Restore: `git checkout -- roles/vfio_boot/templates/entry.conf.j2`

### 6. cryptdevice instead of rd.luks.name
- Break: `sed -i 's|rd.luks.name={{ vfio_boot_luks_uuid }}={{ luks_mapper_name }}|cryptdevice=UUID={{ vfio_boot_luks_uuid }}:{{ luks_mapper_name }}|' roles/vfio_boot/templates/entry.conf.j2`
- Red: render suite - wrong initramfs dialect; sd-encrypt would ignore
  it in silence and park the boot in the initramfs.
- Restore: `git checkout -- roles/vfio_boot/templates/entry.conf.j2`

### 7. Duplicate kernel parameter key
- Break: `sed -i 's|"nvidia-drm.modeset=1 modprobe.blacklist=nouveau"|"nvidia-drm.modeset=1 modprobe.blacklist=nouveau rw"|' roles/vfio_boot/defaults/main.yml`
- Red: render suite - duplicate-key detection (`rw` already lives on
  the contract-composed root line).
- Restore: `git checkout -- roles/vfio_boot/defaults/main.yml`

## roles/network_domains

### 8. The lab receives a forward element
- Break: `sed -i "s|{% if item.forward == 'nat' %}|{% if true %}|" roles/network_domains/templates/net.xml.j2`
- Red: render suite - the strict boolean equivalence
  (isolated <=> no `<forward>` at all).
- Restore: `git checkout -- roles/network_domains/templates/net.xml.j2`

### 9. Truncated XML
- Break: `sed -i 's|</network>||' roles/network_domains/templates/net.xml.j2`
- Red: render suite - the real judge (python `ET.parse`) dies with a
  ParseError before any assert is even reached.
- Restore: `git checkout -- roles/network_domains/templates/net.xml.j2`

## roles/lab_isolation

### 10. flush ruleset as a real directive
- Break: `sed -i 's|^flush table inet lab_isolation$|flush ruleset|' roles/lab_isolation/templates/lab-isolation.nft.j2`
- Red: render suite - matrix invariants. **Note:** `nft -c` BLESSES
  this mutation (valid syntax); only the anchored semantic pin catches
  it. This single mutation justifies the whole level-2 layer.
- Restore: `git checkout -- roles/lab_isolation/templates/lab-isolation.nft.j2`

### 11. Halved deny matrix
- Break: `sed -i 's|{% if a.name != b.name %}|{% if a.name < b.name %}|' roles/lab_isolation/templates/lab-isolation.nft.j2`
- Red: render suite - pair count no longer equals n*(n-1).
- Restore: `git checkout -- roles/lab_isolation/templates/lab-isolation.nft.j2`

### 12. restart instead of reload
- Break: `sed -i 's|state: reloaded|state: restarted|' roles/lab_isolation/handlers/main.yml`
- Red: render suite - reload-only pin (on Arch the unit's stop action
  flushes the whole ruleset: a restart wipes libvirt's NAT).
- Restore: `git checkout -- roles/lab_isolation/handlers/main.yml`

## roles/gpu_handoff

### 13. Inverted trust ladder
- Break: `sed -i 's/trust > current/trust < current/' roles/gpu_handoff/files/qemu`
- Red: bats - three tests at once (downgrade, lateral, upgrade-refused).
- Restore: `git checkout -- roles/gpu_handoff/files/qemu`

### 14. Phase guard removed
- Break: `sed -i '/== "prepare"/d' roles/gpu_handoff/files/qemu`
- Red: bats - "non-prepare phases pass instantly, even for an upgrade".
- Restore: `git checkout -- roles/gpu_handoff/files/qemu`

### 15. services rendered into the rotation
- Break: `sed -i 's/{% endfor %}/{% endfor %}\nservices 2/' roles/gpu_handoff/templates/rotation.j2`
- Red: render suite - rotation invariants ("services never joins it",
  and the line count no longer matches the contract map).
- Restore: `git checkout -- roles/gpu_handoff/templates/rotation.j2`
