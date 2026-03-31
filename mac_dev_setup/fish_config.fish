if status is-interactive
    # Commands to run in interactive sessions can go here

    # Add npm global bin to PATH (for cclsp and other global npm packages)
    fish_add_path /root/.node_modules/bin

    # Use ripgrep for Ctrl+T to search files (faster than default find)
    set -gx FZF_CTRL_T_COMMAND 'rg --files --hidden --follow --glob "!.git" 2>/dev/null'

    # Load fzf key bindings (Ctrl+T, Ctrl+R, Alt+C)
    # Path will be set by fzf installer
    if test -f ~/.fzf/shell/key-bindings.fish
        source ~/.fzf/shell/key-bindings.fish
        fzf_key_bindings
    end

    # Git prompt configuration
    set -g __fish_git_prompt_showdirtystate 1
    set -g __fish_git_prompt_showstashstate 1
    set -g __fish_git_prompt_showuntrackedfiles 1
    set -g __fish_git_prompt_showupstream auto
    set -g __fish_git_prompt_char_dirtystate '*'
    set -g __fish_git_prompt_char_stagedstate '+'
    set -g __fish_git_prompt_char_untrackedfiles '?'
    set -g __fish_git_prompt_char_stashstate '$'
    set -g __fish_git_prompt_char_upstream_ahead '↑'
    set -g __fish_git_prompt_char_upstream_behind '↓'
    set -g __fish_git_prompt_char_upstream_equal ''
end

## enable preview window for ctrl+t
# Use bat for pretty previews if installed
# set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --preview 'bat --style=numbers --color=always --line-range 1:300 {}'"

# If bat isn't installed, fall back to `cat`
# set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --preview 'cat {}'"


## preview for ctrl+r
#function fzf_history_search
#    history | fzf --preview "echo {}" --preview-window=down:3:wrap
#end

#bind \cr fzf_history_search

# Alias vim to nvim
alias vim="nvim"
alias vi="nvim"

# set nvim as default editor
set -gx EDITOR nvim
set -gx VISUAL nvim

# Allow pip to install system-wide in containers
set -gx PIP_BREAK_SYSTEM_PACKAGES 1

# add anthropic api key

# SSH Agent forwarding fix for tmux
# When SSH_AUTH_SOCK is set (forwarded agent), create a stable symlink
# so tmux sessions can find the agent after reconnecting
if test -n "$SSH_AUTH_SOCK" -a "$SSH_AUTH_SOCK" != "$HOME/.ssh/agent_sock"
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent_sock"
    set -gx SSH_AUTH_SOCK "$HOME/.ssh/agent_sock"
end

# Fix stale SSH agent socket (e.g., after tmux reattach)
# If current socket doesn't work, find a working one
function fix_ssh_agent --description "Find and use a working SSH agent socket"
    # First check if current socket works
    if ssh-add -l >/dev/null 2>&1
        return 0
    end

    # Current socket is stale, find a working one
    for sock in /tmp/ssh-*/agent.*
        if test -S "$sock"
            if SSH_AUTH_SOCK=$sock ssh-add -l >/dev/null 2>&1
                ln -sf "$sock" "$HOME/.ssh/agent_sock"
                set -gx SSH_AUTH_SOCK "$HOME/.ssh/agent_sock"
                return 0
            end
        end
    end
    return 1
end

# Auto-fix on shell startup if socket seems stale
if test -n "$SSH_AUTH_SOCK"
    if not ssh-add -l >/dev/null 2>&1
        fix_ssh_agent
    end
end

# SSH Agent setup for Fish + Tmux
# Only start agent if SSH_AUTH_SOCK is not already set (e.g., from agent forwarding)
if test -z "$SSH_AUTH_SOCK"
    set -gx SSH_ENV $HOME/.ssh/environment

    function start_agent
        echo "Starting SSH agent..."
        ssh-agent -c | sed 's/^echo/#echo/' > $SSH_ENV
        chmod 600 $SSH_ENV
        source $SSH_ENV > /dev/null
        ssh-add ~/.ssh/id_ed25519 2>/dev/null
    end

    function test_identities
        ssh-add -l > /dev/null 2>&1
        return $status
    end

    # Check if agent is running
    if test -n "$SSH_AGENT_PID"
        if not ps -p $SSH_AGENT_PID > /dev/null
            start_agent
        end
    else if test -f $SSH_ENV
        source $SSH_ENV > /dev/null
        if not test_identities
            start_agent
        end
    else
        start_agent
    end
end
