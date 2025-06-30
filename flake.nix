{
  description = "Development environment with Node.js and .NET Core";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Common packages used across different shells
        commonPackages = with pkgs; [
          qmk
          keymapviz
        ];
      in
      {
        # Development shells
        devShells = {
          # Default development environment
          default = pkgs.mkShell {
            name = "dev-environment";
            buildInputs = commonPackages;
            
            shellHook = ''
              echo "🚀 QMK Development environment loaded!"
              echo "Available tools:"
              echo "  - QMK CLI: $(qmk --version)"
              
              # Set up QMK paths
              export QMK_HOME="$(realpath qmk_firmware)"
              export QMK_USERSPACE="$(realpath qmk_userspace)"
              
              # Configure QMK CLI
              qmk config user.qmk_home="$QMK_HOME" 2>/dev/null || true
              qmk config user.overlay_dir="$QMK_USERSPACE" 2>/dev/null || true
              
              echo "  - QMK Home: $QMK_HOME"
              echo "  - QMK Userspace: $QMK_USERSPACE"
              echo ""
              echo "Quick commands:"
              echo "  - nix run .#compile       # Compile CRKBD keymap"
              echo "  - nix run .#setup-qmk     # Setup QMK submodules"
              echo "  - nix run .#update-env    # Update environment"
            '';
          };
        };

        # Packages you can build
        packages = {
          default = pkgs.buildEnv {
            name = "dev-environment";
            paths = commonPackages;
            # Add a version or hash so Nix knows when to upgrade
            meta = {
              description = "Development environment";
              version = builtins.hashString "sha256" (builtins.toJSON commonPackages);
            };
          };
        };

        # Apps you can run with 'nix run'
        apps = {

          # Update script
          update-env = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "update-env" ''
              echo "🔄 Updating development environment..."
              nix flake update
              echo "📦 Cleaning profile and reinstalling..."
              nix profile remove '.*' 2>/dev/null || true
              nix profile install .#default
              echo "✅ Environment updated!"
              echo "ℹ️  You may need to run 'hash -r' to refresh your PATH"
            '';
          };
          
          # Setup QMK submodules
          setup-qmk = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "setup-qmk" ''
              echo "🔄 Setting up QMK submodules..."
              
              if [ ! -d "qmk_firmware" ]; then
                echo "❌ qmk_firmware directory not found!"
                exit 1
              fi
              
              cd qmk_firmware
              echo "📦 Initializing QMK submodules (this may take a while)..."
              git submodule update --init --recursive
              
              cd ..
              
              cd qmk_userspace
              git checkout soycabanillas-keymap 2>/dev/null || true

              cd ..

              # Configure QMK
              export QMK_HOME="$(realpath qmk_firmware)"
              export QMK_USERSPACE="$(realpath qmk_userspace)"
              
              qmk config user.qmk_home="$QMK_HOME"
              qmk config user.overlay_dir="$QMK_USERSPACE"
              
              echo "✅ QMK setup complete!"
              echo "  - QMK Home: $QMK_HOME"
              echo "  - QMK Userspace: $QMK_USERSPACE"
              echo "Run \"nix run .#update-env\" to update packages."
            '';
          };

          # Compile CRKBD keymap
          compile = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "compile" ''
              echo "🔄 Compiling QMK firmware..."
              
              # Set up environment
              export QMK_HOME="$(realpath qmk_firmware)"
              export QMK_USERSPACE="$(realpath qmk_userspace)"
              
              # Configure QMK CLI
              qmk config user.qmk_home="$QMK_HOME" 2>/dev/null || true
              qmk config user.overlay_dir="$QMK_USERSPACE" 2>/dev/null || true
              
              # Check if submodules are initialized
              if [ ! -f "qmk_firmware/lib/lufa/LUFA/makefile" ]; then
                echo "⚠️  QMK submodules not initialized. Running setup..."
                cd qmk_firmware
                git submodule update --init --recursive
                cd ..
              fi
              
              echo "🔨 Compiling CRKBD keymap..."
              qmk compile -kb crkbd/rev1 -km soycabanillas
              
              if [ $? -eq 0 ]; then
                echo "✅ QMK firmware compiled successfully!"
                echo "📁 Check the qmk_firmware directory for the compiled firmware file."
              else
                echo "❌ Compilation failed. Check the output above for errors."
                exit 1
              fi
            '';
          };

          # Sync with upstream QMK userspace
          sync-upstream = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "sync-upstream" ''
              echo "🔄 Syncing with upstream QMK userspace..."
              
              cd qmk_userspace
              
              # Store current branch
              CURRENT_BRANCH=$(git branch --show-current)
              echo "📍 Current branch: $CURRENT_BRANCH"
              
              # Update main branch
              echo "⬇️  Fetching upstream changes..."
              git fetch upstream
              git checkout main
              git merge upstream/main
              git push origin main
              
              # Rebase development branch
              if [ "$CURRENT_BRANCH" != "main" ]; then
                echo "🔄 Rebasing $CURRENT_BRANCH on updated main..."
                git checkout "$CURRENT_BRANCH"
                git rebase main
                
                echo "⬆️  Pushing rebased branch..."
                git push --force-with-lease origin "$CURRENT_BRANCH"
              fi
              
              echo "✅ Sync complete!"
              echo "📍 Back on branch: $(git branch --show-current)"
            '';
          };

          # Git setup command
          setup-git = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "setup-git" ''
              echo "🔧 Setting up Git configuration..."
              
              read -p "Enter your name: " name
              read -p "Enter your email: " email

              git config user.name "$name"
              git config user.email "$email"

              cd qmk_firmware
              git config user.name "$name"
              git config user.email "$email"
              cd ..
              
              cd qmk_userspace
              git config user.name "$name"
              git config user.email "$email"
              cd ..

              echo ""
              echo "This configuration will be used for all Git operations in this container."
            '';
          };
        };
      }
    );
}