{
  description = "Dev shell for p07 — Hetzner Cloud MicroK8s environment tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
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
            terraform
            kubernetes-helm # helm
            kubectl
            nodejs_22
            redis # redis-cli
            azwi
            kubelogin # Azure kubelogin, used by the .kube/oidc-config exec block
            jq
            python3 # seeds .venv — Terraform's ansible provider interpreter (main.tf)
          ];

          shellHook = ''
            if [ ! -d .venv ]; then
              echo "No .venv found — run 'bash scripts/install_dependencies.sh' to seed the"
              echo "Python virtual environment, Ansible collections, and Terraform backend."
            fi
          '';
        };
      });
    };
}
