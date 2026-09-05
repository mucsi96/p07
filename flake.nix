{
  description = "Dev shell for p07 Netcup k3s environment tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            # Terraform is distributed under the BUSL license, which nixpkgs
            # marks as unfree.
            config.allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
          }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            azure-cli # az
            curl
            terraform
            kubernetes-helm # helm
            kubectl
            nodejs_22
            redis # redis-cli
            kubelogin # Azure kubelogin, used by the .kube/oidc-config exec block
            jq
            openssh # ssh-agent, ssh-add
            python3 # seeds .venv — Terraform's ansible provider interpreter (main.tf)
          ];

          shellHook = ''
            # VS Code workspaceFolder equivalent: the project root is where the dev where the dev
            # shell is entered. Fall back to the git toplevel when entered from
            # a subdirectory.
            if [ -z "$KUBECONFIG" ]; then
              _project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              export KUBECONFIG="$_project_root/.kube/admin-config"
            fi

            if [ ! -d .venv ]; then
              echo "No .venv found — run 'bash scripts/install_dependencies.sh' to seed the"
              echo "Python virtual environment, Ansible collections, and Terraform backend."
            fi

            # Remind about the Twingate client. Terraform and Ansible reach the
            # cluster through the Twingate tunnel, so the client must be connected
            # before scripts/create.sh runs. The daemon is a system-level systemd
            # service installed outside the flake (see README). On this headless
            # WSL box Twingate cannot open a browser for login, so we only check
            # status and point at the console-based auth flow — connecting is left
            # to the user so the shell never blocks on a browser that never opens.
            if command -v twingate >/dev/null 2>&1; then
              if [ "$(twingate status 2>/dev/null)" != "online" ]; then
                echo "Twingate is not connected. To connect:"
                echo "  1. twingate start          # starts the daemon (sudo) and connects"
                echo "  2. if it asks to authenticate, run 'twingate-notifier console' in"
                echo "     another terminal, then open the printed URL in your Windows"
                echo "     browser and log in."
              fi
            fi
          '';
        };
      });
    };
}
