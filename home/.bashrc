__git_branch() { git branch 2>/dev/null | sed -n 's/^* \(.*\)/ (\1)/p'; }
PS1='\[\033[0;32m\]AGENT\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\]:\[\033[0;34m\]\w\[\033[0;33m\]$(__git_branch)\[\033[0m\]\$ '