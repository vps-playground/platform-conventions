# platform-conventions task runner

skills_dir := env_var('HOME') / ".claude" / "skills"
skills_src := justfile_directory() / "skills"

# Skills shipped from this repo. To add a new one: drop it under skills/<name>/
# and append the name to this list.
SKILLS := "convention-uplift workload-bootstrap"

# Default target lists available recipes.
default:
    @just --list

# Install every skill in SKILLS by symlinking it into ~/.claude/skills/.
# Idempotent: existing correct symlinks are kept; conflicting ones fail loud
# unless you `just reinstall`.
install:
    @mkdir -p "{{skills_dir}}"
    @for name in {{SKILLS}}; do \
        src="{{skills_src}}/$name"; \
        link="{{skills_dir}}/$name"; \
        if [ ! -d "$src" ]; then \
            echo "[fail] missing skill source: $src"; exit 1; \
        fi; \
        if [ -L "$link" ]; then \
            existing=$(readlink "$link"); \
            if [ "$existing" = "$src" ]; then \
                echo "[ok]   already installed: $link"; \
                continue; \
            else \
                echo "[fail] conflicting symlink: $link -> $existing"; \
                echo "       run 'just reinstall' to replace it"; \
                exit 1; \
            fi; \
        elif [ -e "$link" ]; then \
            echo "[fail] $link exists and is not a symlink — remove it manually"; \
            exit 1; \
        fi; \
        ln -s "$src" "$link"; \
        echo "[ok]   installed $name -> $link"; \
    done

# Remove every skill symlink owned by this repo.
uninstall:
    @for name in {{SKILLS}}; do \
        link="{{skills_dir}}/$name"; \
        if [ -L "$link" ]; then \
            rm "$link"; \
            echo "[ok]   removed $link"; \
        else \
            echo "[skip] nothing to remove at $link"; \
        fi; \
    done

# Force reinstall (remove existing links, then install).
reinstall: uninstall install

# Show install status of every skill in SKILLS.
status:
    @for name in {{SKILLS}}; do \
        link="{{skills_dir}}/$name"; \
        src="{{skills_src}}/$name"; \
        if [ -L "$link" ]; then \
            target=$(readlink "$link"); \
            if [ "$target" = "$src" ]; then \
                echo "[ok]   installed: $link -> $target"; \
            else \
                echo "[warn] symlink points elsewhere: $link -> $target"; \
            fi; \
        elif [ -e "$link" ]; then \
            echo "[warn] $link exists but is not a symlink"; \
        else \
            echo "[none] $name not installed"; \
        fi; \
    done
