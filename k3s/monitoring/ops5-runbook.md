# Ops 5 Minecraft Observability Runbook

## Setup notes

This cluster runs on a single AWS Academy EC2 instance using k3s. Git was installed manually on the EC2 instance so the repository could be cloned:

```bash
sudo dnf install git -y
git clone -b ops5-oberservability https://github.com/David-Gesl/ops4-minecraft.git
cd ops4-minecraft