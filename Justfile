# platform-conventions task runner

skill_name := "convention-uplift"
skills_dir := env_var('HOME') / ".claude" / "skills"
skill_src := justfile_directory() / "skills" / skill_name
skill_link := skills_dir / skill_name

# Default target lists available recipes.
default:
    @just --list

# Install the convention-uplift skill by symlinking it into ~/.claude/skills/.
install:
    @mkdir -p "{{skills_dir}}"
    @if [ -L "{{skill_link}}" ]; then \
        existing=$(readlink "{{skill_link}}"); \
        if [ "$existing" = "{{skill_src}}" ]; then \
            echo "[ok] already installed: {{skill_link}}"; \
            exit 0; \
        else \
            echo "[fail] conflicting symlink: {{skill_link}} -> $existing"; \
            echo "       run 'just reinstall' to replace it"; \
            exit 1; \
        fi; \
    elif [ -e "{{skill_link}}" ]; then \
        echo "[fail] {{skill_link}} exists and is not a symlink — remove it manually"; \
        exit 1; \
    fi
    @ln -s "{{skill_src}}" "{{skill_link}}"
    @echo "[ok] installed {{skill_name}} -> {{skill_link}}"

# Remove the convention-uplift skill symlink.
uninstall:
    @if [ -L "{{skill_link}}" ]; then \
        rm "{{skill_link}}"; \
        echo "[ok] removed {{skill_link}}"; \
    else \
        echo "[skip] nothing to remove at {{skill_link}}"; \
    fi

# Force reinstall (remove existing link, then install).
reinstall: uninstall install

# Show install status of the skill.
status:
    @if [ -L "{{skill_link}}" ]; then \
        target=$(readlink "{{skill_link}}"); \
        if [ "$target" = "{{skill_src}}" ]; then \
            echo "[ok] installed: {{skill_link}} -> $target"; \
        else \
            echo "[warn] symlink points elsewhere: {{skill_link}} -> $target"; \
        fi; \
    elif [ -e "{{skill_link}}" ]; then \
        echo "[warn] {{skill_link}} exists but is not a symlink"; \
    else \
        echo "[none] not installed"; \
    fi
