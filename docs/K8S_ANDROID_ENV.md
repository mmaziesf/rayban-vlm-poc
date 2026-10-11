# Android build + test stack as Kubernetes manifests

**Location:** `infra/k8s/`. Validated with `kustomize build` + `kubeconform -strict` (6/6 resources per overlay).
**Not deployed:** there's no cluster or credentials. **Image not built:** there's no container runtime on the box.

## Layout
| File | Role |
|---|---|
| `Dockerfile.android` | One image: Debian trixie, JDK 17, cmdline-tools, platform 35, build-tools 35, emulator, API 29 x86_64 image + AVD, kotlinc 2.4.21, git, socat |
| `emulator-entry.sh` | Boots the AVD headless (`ACCEL=on\|off`). Publishes adb on `:5556` with socat; readiness = `sys.boot_completed` |
| `base/build-job.yaml` | Job: clone → `core/run-tests.sh` → `assembleDebug` + `assembleDebugAndroidTest` → APKs to PVC |
| `base/emulator.yaml` | Deployment + Service `emulator:5555`. **TCG by default**: no privileges, 4 CPU / 3–4 GiB |
| `base/test-job.yaml` | Job: wait for APKs + boot → install → `am instrument -e timeoutScale $TIMEOUT_SCALE` (MockLoopTest) → `smoke.sh` → results to PVC |
| `overlays/tcg` | Any cluster (slow, safe) |
| `overlays/kvm` | Adds nodeSelector `nested-virtualization: enabled`, `/dev/kvm` hostPath, `privileged`, `ACCEL=on`, `TIMEOUT_SCALE=1` |
| `up.sh [tcg\|kvm]` / `down.sh` | Apply and wait for the jobs / delete the namespace (incl. PVC) |

## Would k8s beat this box?
- **On this box: no.** A local kind/k3s shares the box kernel: still no usable KVM, still no binder for redroid. It would only add overhead to the TCG emulator, which already works directly.
- **On a real cluster with KVM-capable nodes: yes.** That means GKE Standard node pools created with `--enable-nested-virtualization` (Ubuntu containerd image; GKE docs name Android emulators as a use case), or bare-metal nodes.
  - About 10× faster than TCG.
  - Parallel shards.
  - Reproducible up/down.
  - Becomes the natural CI for M2/M4/M5 regression runs.
  - Costs node-hours, and needs Arash's cloud project, a registry, and a kube context.
- **redroid in k8s** (Android in a container, no VM): fast and light, but every node needs `binder_linux` (and ashmem/memfd) loaded, i.e. a privileged DaemonSet or a custom node image. It's an option on self-managed Ubuntu nodes and adds no value over KVM nodes for us. Not on GKE COS.
- **Device plugin instead of `privileged`:** kubevirt's KVM device plugin exposes `devices.kubevirt.io/kvm`. The project marks itself "not finalized", so the overlay uses GKE's documented privileged + hostPath pattern.

## To bring it up (needs Arash once)
1. Cloud project + GKE Standard cluster; node pool, e.g.:
   `gcloud container node-pools create emu --cluster=C --machine-type=n2-standard-8 --image-type=UBUNTU_CONTAINERD --enable-nested-virtualization --node-labels=nested-virtualization=enabled`
2. Push the repo somewhere clonable and set `REPO_URL` in `base/build-job.yaml`.
3. Build + push the image: `docker build -f infra/k8s/Dockerfile.android -t REGISTRY/glance-android:0.1 .`, then set `newName` in `base/kustomization.yaml`.
4. `infra/k8s/up.sh kvm`. Results land in the PVC at `/work/out/results/`.

## Sources
- GKE nested virtualization: https://cloud.google.com/kubernetes-engine/docs/how-to/nested-virtualization
- Google emulator containers (need `/dev/kvm`; cloud needs nested virt or bare metal): https://github.com/google/android-emulator-container-scripts
- KubeVirt KVM device plugin: https://github.com/kubevirt/kubernetes-device-plugins/blob/master/docs/README.kvm.md
- docker-android (also KVM): https://github.com/budtmo/docker-android
- redroid deploy/kernel modules: https://github.com/remote-android/redroid-doc/tree/master/deploy , https://github.com/remote-android/redroid-modules
