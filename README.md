# ACE-Install-Helper
**Initial author: Sean Tu — [@sajtu on GitHub](https://github.com/sajtu)**
***https://github.com/sajtu/ACE-Install-Helper.git

## Read before running — disclaimer and responsibility

**Provided “as is” and “as available,” without warranty of any kind. Review the
code before executing it. Do not rely on this README, a successful test, or any
project description as proof that the scripts are safe or suitable for your
system.**

Sean Tu has successfully tested and used the helper in their own environment,
but makes no guarantee of compatibility, safety, reliability, or results in
other environments or with future upstream changes. This project is shared for
education and community benefit.

Perform your own due diligence: inspect the scripts and the software they
download, consult official documentation and licenses, and decide whether the
setup is appropriate for your environment. Maintain recoverable backups and
consider testing in an isolated lab or disposable environment before using a
machine with important data or services. You are responsible for your decision
to execute the code, the privileges you grant, and your system’s configuration,
credentials, access controls, and recovery arrangements.

To the maximum extent permitted by applicable law, the author and contributors
disclaim all express and implied warranties, including merchantability, fitness
for a particular purpose, and non-infringement, and shall not be liable for
claims, losses, or damages arising from use of, inability to use, or reliance on
this project. This includes data loss, system damage, downtime, lost profits,
and direct, indirect, incidental, special, or consequential damages, even if
advised of their possibility. This notice does not exclude rights or obligations
that cannot legally be excluded.

**This README is an overview of this helper, not a replacement for official
ACE-Step documentation or third-party guides. Follow the original projects’
documentation as the source of truth for their software and models.**

## Purpose and scope

An interactive installation and launch helper for **ACE-Step 1.5 on compatible Ubuntu systems with an NVIDIA GPU**.

The purpose is straightforward: download ACE-Step, check prerequisites, set up an isolated environment, and get an instance running with fewer manual steps and less command memorization. It was created to simplify the author’s own setup and is shared to help others do the same. Hardware and software compatibility checks still apply; it is not a promise of support for every Ubuntu/NVIDIA combination.

Created in the spirit of sharing, experimentation, and education. Questions, feedback, and bug reports can be submitted through this repository’s [GitHub Issues](https://github.com/sajtu/ACE-Install-Helper/issues). Please omit passwords, tokens, and other private information from reports.

This is an independent helper project. It is not affiliated with, sponsored by, endorsed by, or an official product of ACE-Step, its developers, NVIDIA, Ubuntu, or the other projects listed below. It automates setup of their software; it does not claim authorship or ownership of that software or its models.

## Which ACE project does this install?

This helper targets **[ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5),
the AI audio/music-generation project**. It is not an installer for unrelated
projects named ACE, or for the separate ACE Studio application.

In brief, ACE-Step offers local music generation using descriptions and lyrics,
with workflows that may include vocals, source-audio covers/remixes, and edits.
Capabilities, hardware requirements, supported models, and output quality depend
on the upstream version and configuration. Results can vary, including lyric
omissions, timing differences, and audio artifacts.

Use the **[official repository and README](https://github.com/ace-step/ACE-Step-1.5)**,
**[official documentation](https://ace-step.github.io/ACE-Step-1.5/)**, and
**[upstream model pages](https://huggingface.co/ACE-Step)** for current details.
The short description here is only to identify the intended project and avoid
confusion with similarly named tools.

## What this helper does

- Checks Ubuntu, CPU architecture, NVIDIA driver availability, GPU memory, disk space, and access to required download hosts.
- Prompts before installing missing system packages, `uv`, and an isolated Python runtime.
- Stops if prerequisites are missing, installation is declined, or a required operation fails.
- Installs ACE-Step in its own Python environment without requiring manual environment activation.
- Detects an existing installation and spot-checks files, packages, and model headers for completeness and truncation.
- Offers to repair an existing installation, or start a complete installation without reinstalling it.
- Downloads the default model bundle and creates `start-ace.sh` inside the ACE installation.
- Optionally adds the ACE directory to PATH and creates a `start-ace` alias in Bash or Zsh configuration, with a backup.
- Uses indented terminal output and extra spacing for readability.

The launcher provides interactive access and login choices, automatic GPU precision selection, model selection, background operation, and process control **without systemd**.

The scripts also apply guarded compatibility patches for the known precision-override and Flow Edit CPU-offloading issues encountered during development. They save source backups and stop when the expected source structure does not match. These are local helper modifications, not upstream guarantees.

## Requirements and dependencies

This helper targets **Ubuntu x86-64 with an NVIDIA GPU**, using Bash. The author has successfully used it in their own Ubuntu 24.04 environment with a Quadro RTX 6000. Other configurations are not guaranteed.

| Requirement | Current helper policy |
|---|---|
| Operating system | Ubuntu, x86-64 |
| NVIDIA driver | Working `nvidia-smi`; driver version at least `570.26` |
| GPU | Launcher requires Turing / compute capability 7.5 or newer |
| GPU memory | Installer checks at least 8 GiB total and currently free VRAM; actual model requirements can be higher |
| Storage | At least 30 GiB free during installation/repair; additional models require more |
| Python | Isolated, `uv`-managed Python 3.11 |
| Network | Access to GitHub, Python/package hosts, and model-download hosts |
| Permissions | Normal user account; `sudo` when missing Ubuntu packages must be installed |

System packages checked by the installer:

```text
git curl ca-certificates ffmpeg libsndfile1 build-essential util-linux
```

`util-linux` supplies `flock` and `setsid`. The installer uses `uv` to install ACE-Step’s Python dependencies, including PyTorch, Gradio, Transformers, and audio libraries, as specified by the upstream project.

**The current helper does not install or upgrade NVIDIA drivers.** If the driver check fails, install a suitable Ubuntu-supported driver and reboot before retrying. There is no need to activate your existing Ollama/vLLM environment. Free GPU memory by unloading other models before installation or startup.

The installer’s resource thresholds are preliminary checks, not proof that every model or song duration will fit. Large models, FP32, and long generations can require substantially more resources.

## Download

Using HTTPS:

```bash
git clone https://github.com/sajtu/ACE-Install-Helper.git
```

Or using SSH, with a GitHub SSH key already configured:

```bash
git clone git@github.com:sajtu/ACE-Install-Helper.git
```

## Install

Review the scripts before executing them. Run as the user who should own the installation:

```bash
cd ACE-Install-Helper
chmod +x install-ace.sh
./install-ace.sh
```

Alternatively:

```bash
bash install-ace.sh
```

The default destination is:

```text
$HOME/apps/ACE-Step-1.5
```

Running as root uses root’s home directory. Running as a normal user installs into that user’s home directory and requests elevated privileges only for missing system packages.

### Existing installations and repair

If a complete installation is found, the installer asks whether to reinstall/repair it. If you decline, it asks whether to start the existing installation.

An incomplete installation offers repair. Repair refreshes Python dependencies, reuses existing model downloads, and replaces the launcher after saving a backup. It does not erase the entire installation or automatically update the upstream Git checkout. ACE must be stopped before repair proceeds.

Spot checks are not exhaustive integrity checks or an end-to-end generation test. If model downloads remain damaged, further manual diagnosis may be necessary.

After successful installation/repair, the helper offers shell setup and startup. Startup problems are reported separately from installation completion.

### Installer options

**The installer currently accepts no CLI switches**, including no `--help` switch. It is interactive. Configure its destination and selected GPU with environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `ACESTEP_INSTALL_DIR` | `$HOME/apps/ACE-Step-1.5` | Absolute installation path |
| `ACESTEP_GPU_INDEX` | `0` | Physical GPU index shown by `nvidia-smi` |

Example:

```bash
ACESTEP_INSTALL_DIR="$HOME/apps/ACE-Step-1.5" \
ACESTEP_GPU_INDEX=0 \
bash install-ace.sh
```

## Start ACE

If you accepted shell setup, open a new shell or source the updated profile:

```bash
source ~/.bashrc
start-ace
```

For Zsh, source the `.zshrc` used by your account instead.

Without an alias, run:

```bash
"$HOME/apps/ACE-Step-1.5/start-ace.sh"
```

You do not need to activate a virtual environment or set up `uv` manually. The launcher locates the user-installed `uv` and uses ACE’s isolated environment.

### Interactive defaults

1. **Allow LAN browser access?** Default: **No**. Enter keeps the server on `127.0.0.1`.
2. **Enable browser login protection?** Default: **Yes**. Enter enables it.
3. If enabled, enter a username and password. Password input is hidden. A blank password shows an error and returns to the login-protection question rather than exiting.

After these choices, ACE starts in the background and returns your shell. Initialization continues after the launch message. Check the logs for readiness.

LAN mode binds to all interfaces and uses HTTP. Login protection does not encrypt the connection. For private remote access, use localhost with an SSH tunnel or a suitably configured HTTPS proxy.

The helper does not modify firewall rules, configure Caddy, create public sharing links, or install a systemd service.

### Launcher switches

| Switch | Purpose |
|---|---|
| `--help`, `-h` | Display usage |
| `--local` | Bind localhost; skip the LAN-choice prompt |
| `--lan` | Bind all interfaces; skip the LAN-choice prompt |
| `--auth` | Enable login protection; request credentials unless supplied |
| `--no-auth` | Disable login protection and skip its prompt |
| `--username NAME` | Supply the browser username |
| `--password-file FILE` | Read one nonempty password line from a file |
| `--non-interactive` | Require explicit access/login choices and no credential prompts |
| `--auto` | Choose GPU precision automatically |
| `--fp32` | Force FP32 |
| `--fp16` | Force FP16; may overflow on some ACE/GPU combinations |
| `--model NAME` | Select a supported, already-downloaded music model |
| `--gpu INDEX` | Select a physical NVIDIA GPU |
| `--port NUMBER` | Change the web port; default `7860` |
| `--background` | Start detached; default behavior |
| `--foreground` | Keep the server attached to the terminal |
| `--status` | Check the recorded server process |
| `--logs` | Print the last 80 background log lines |
| `--stop` | Send SIGTERM to the managed process group |
| `--kill` | Send SIGKILL to force termination |

Explicit switches skip their corresponding questions. For example, `--local` alone still asks whether to enable browser login.

Fully non-interactive, without browser login:

```bash
start-ace --non-interactive --local --no-auth
```

With browser login, prepare a private password file using an editor, give it restrictive permissions, then launch:

```bash
chmod 600 "$HOME/.ace-browser-password"

start-ace --non-interactive --lan --auth \
  --username "$USER" \
  --password-file "$HOME/.ace-browser-password"
```

The file must contain one nonempty password line. Passwords are not passed in the operating-system command argument list. Do not commit password files to Git.

### GPU precision and environment defaults

Auto precision chooses **FP32 on Turing** and **BF16 on Ampere or newer**. Turing does support FP16; FP32 is a stability policy motivated by ACE FP16 overflow observed on the author’s Quadro setup.

The launcher enables CPU offloading when FP32 is selected. Forced precision remains available for testing, but does not guarantee compatibility.

Environment defaults are `ACESTEP_GPU_INDEX`, `ACESTEP_PORT`, `ACESTEP_DTYPE`, and `ACESTEP_MODEL`. CLI switches override the corresponding defaults. `ACESTEP_DTYPE` accepts `auto`, `float32`, `float16`, or `bfloat16`; native BF16 is rejected on pre-Ampere GPUs.

## Private remote browser access with SSH

On the Ubuntu host, start localhost-only ACE:

```bash
start-ace --local --no-auth
```

On your Mac or other client, open a separate terminal and run:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:7860:127.0.0.1:7860 \
  your-user@your-ubuntu-host
```

Replace the user and hostname with your own. Then open:

```text
http://localhost:7860
```

The first localhost endpoint is on your client; the second is on the Ubuntu host. SSH carries the connection privately, so you do not need LAN access or to open port 7860 on the host’s firewall. SSH itself must be available and reachable.

Keep the tunnel terminal open. Ctrl+C closes the tunnel; it does not stop background ACE.

If port 7860 is occupied on your client, use local port 7861:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:7861:127.0.0.1:7860 \
  your-user@your-ubuntu-host
```

Open `http://localhost:7861`. If you changed ACE’s server port, replace the final port in the forwarding rule accordingly.

## Process control and logs

```bash
start-ace --status
start-ace --logs
start-ace --stop
```

If graceful shutdown is unsuccessful:

```bash
start-ace --kill
```

The background process survives SSH disconnection. These controls apply to launches managed by this helper, not unrelated ACE processes started manually or with an older launcher.

The scripts use a kernel-backed lock to prevent duplicate launches in the same installation. A crash releases the lock automatically. Session metadata records process details, and process start-time checks guard against signalling a reused PID. The lock file intentionally remains on disk; do not delete it while ACE is running.

Status confirms that the recorded process exists, not that model initialization succeeded or the webpage is ready. Background output is appended to `ace-server.log` in the installation directory. Logs may include your prompts and lyrics; review them before sharing.

Foreground mode remains useful for troubleshooting:

```bash
start-ace --local --no-auth --foreground
```

Ctrl+C stops the foreground session. Use `--stop` for a background session.

## Other music models

The launcher supports only these model names:

| Model | Typical generation steps |
|---|---:|
| `acestep-v15-turbo` — default | 8 |
| `acestep-v15-sft` | About 50 |
| `acestep-v15-base` | About 50 |
| `acestep-v15-xl-turbo` | 8 |
| `acestep-v15-xl-sft` | About 50 |
| `acestep-v15-xl-base` | About 50 |

The installer downloads the default bundle. Selecting another model does not download it automatically. Download it first, for example:

```bash
cd "$HOME/apps/ACE-Step-1.5"
"$HOME/.local/bin/uv" run acestep-download --model acestep-v15-sft

./start-ace.sh --local --no-auth --model acestep-v15-sft
```

Choose an appropriate step count in the browser after switching models. XL models need more memory, especially in FP32. For model capabilities and updated guidance, consult the [upstream model documentation](https://github.com/ace-step/ACE-Step-1.5#-model-zoo).

## Troubleshooting

- **`apt update` fails:** resolve the affected repository before installing missing prerequisites. The helper stops rather than bypassing repository security checks.
- **`start-ace` is not found:** open a new shell, source the configured profile, or use the full launcher path.
- **GPU memory is unavailable:** unload other GPU models and retry.
- **Blank browser password:** choose whether to enable login again, then provide a nonempty password if enabled.
- **Webpage is unavailable:** check `--status` and `--logs`; confirm startup finished, the address/port is correct, and the SSH tunnel or LAN route is working.
- **An active session is reported:** use `--status`, then `--stop` if you intend to restart it.
- **A compatibility patch refuses to apply:** preserve the message and source version for diagnosis. Upstream code may have changed; do not assume the old patch is appropriate.

## Third-party acknowledgments and original sources

This independent helper builds on third-party work. The brief descriptions below
identify the main components; they do not replace installation instructions,
security guidance, compatibility information, or license terms from those
projects. **Consult the original sources for authoritative, current details.**

| Project | Brief role in this setup | Original source |
|---|---|---|
| ACE-Step | Intended audio/music-generation application; upstream credits ACE Studio and StepFun | [GitHub and documentation links](https://github.com/ace-step/ACE-Step-1.5) |
| Astral uv | Python and dependency environment tooling | [GitHub](https://github.com/astral-sh/uv) |
| Python | Runtime used by ACE and helper checks | [CPython](https://github.com/python/cpython) |
| PyTorch ecosystem | Tensor, GPU, and audio/image libraries used by upstream | [PyTorch](https://github.com/pytorch/pytorch), [TorchAudio](https://github.com/pytorch/audio), [TorchVision](https://github.com/pytorch/vision) |
| Gradio | Browser interface framework | [GitHub](https://github.com/gradio-app/gradio) |
| Hugging Face ecosystem | Model loading, diffusion tooling, and download clients | [Transformers](https://github.com/huggingface/transformers), [Diffusers](https://github.com/huggingface/diffusers), [Hub](https://github.com/huggingface/huggingface_hub) |
| Qwen | Model families used in upstream text/model components | [Qwen3](https://github.com/QwenLM/Qwen3), [Qwen3-Embedding](https://github.com/QwenLM/Qwen3-Embedding) |
| nano-vLLM | Optional language-model inference component included through ACE | [Upstream](https://github.com/GeeeekExplorer/nano-vllm), [ACE’s copy](https://github.com/ace-step/ACE-Step-1.5/tree/main/acestep/third_parts/nano-vllm) |
| Ubuntu / Canonical and contributors | Operating system and packaged prerequisites | [Ubuntu](https://ubuntu.com/), [Canonical GitHub](https://github.com/canonical) |
| NVIDIA | GPU driver and CUDA ecosystem | [CUDA documentation](https://docs.nvidia.com/cuda/), [GitHub](https://github.com/NVIDIA) |
| FFmpeg | Audio conversion tooling | [Official project](https://ffmpeg.org/), [GitHub mirror](https://github.com/FFmpeg/FFmpeg) |
| libsndfile / SoundFile | Audio-file libraries | [libsndfile](https://github.com/libsndfile/libsndfile), [SoundFile](https://github.com/bastibe/python-soundfile) |
| Git / curl | Source retrieval and downloads | [Git](https://github.com/git/git), [curl](https://github.com/curl/curl) |
| util-linux | Locking and detached-process tools | [GitHub](https://github.com/util-linux/util-linux) |
| GNU and other shell-tool contributors | Bash, file utilities, and output formatting | [Bash](https://www.gnu.org/software/bash/), [Coreutils](https://www.gnu.org/software/coreutils/), [GNU awk](https://www.gnu.org/software/gawk/), [mawk](https://invisible-island.net/mawk/) |
| OpenSSH | Optional private remote access via SSH forwarding | [Official project](https://www.openssh.com/), [GitHub](https://github.com/openssh/openssh-portable) |

Credit and applicable copyrights belong to the respective authors, contributors,
and rights holders. Project names and trademarks are used for identification,
not to imply endorsement or affiliation.

This list is not an exhaustive dependency inventory. Installed packages and
third-party wheels may change with upstream releases. Check the actual versions,
original repositories, and accompanying copyright and license notices.

Any license supplied for this helper covers only material its author has the
right to license. It does not relicense third-party software, model weights, or
content. Code and model licenses may differ; review the original terms before
use or redistribution and preserve applicable notices. The disclaimer near the
top also applies to your use of this overview.
