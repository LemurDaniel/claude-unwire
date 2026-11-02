# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./plugins/unwire

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# ===================   CHECK MANIFESTS OF EVERY AGENT   ====================
# ===========================================================================
#
#   same_identity       Claude, Agent Plugins and Gemini name the same plugin
#                       and version.
#   marketplaces        Claude and Codex marketplaces point at the plugin.
#   skill_names         Every skill folder has a SKILL.md whose name is the
#                       folder name, plus a description.
#   outside_claude      Every SKILL.md with Claude-only names explains them
#                       for other agents.
#

BeforeAll {
    $PLUGIN_ROOT = Join-Path -Path $PSScriptRoot -ChildPath '../..' | Resolve-Path
    $REPO_ROOT   = Join-Path -Path $PLUGIN_ROOT -ChildPath '../..' | Resolve-Path

    function Read-Json([System.String] $Path) {
        return Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
    }

    $Manifests = @{
        claude = Read-Json (Join-Path -Path $PLUGIN_ROOT -ChildPath '.claude-plugin/plugin.json')
        agents = Read-Json (Join-Path -Path $PLUGIN_ROOT -ChildPath 'plugin.json')
        gemini = Read-Json (Join-Path -Path $PLUGIN_ROOT -ChildPath 'gemini-extension.json')
    }
    $SkillFiles = Get-ChildItem -Path (Join-Path -Path $PLUGIN_ROOT -ChildPath 'skills') -Directory
    | ForEach-Object { Join-Path -Path $_.FullName -ChildPath 'SKILL.md' }
}

Describe 'plugin manifests' {
    It 'same_identity: <Agent> names unwire in the version of the Claude manifest' -ForEach @(
        @{ Agent = 'agents' }
        @{ Agent = 'gemini' }
    ) {
        $Manifests[$Agent].name    | Should -Be 'unwire'
        $Manifests[$Agent].version | Should -Be $Manifests.claude.version
        $Manifests.claude.name     | Should -Be 'unwire'
    }

    It 'same_identity: the Agent Plugins manifest has the 1.0.0 schema and no path fields' {
        $Manifests.agents['$schema'] | Should -Be 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
        $Manifests.agents.Keys       | Should -Not -Contain 'skills'
    }

    It 'marketplaces: <File> points unwire at ./plugins/unwire' -ForEach @(
        @{ File = '.claude-plugin/marketplace.json'; Field = 'claude' }
        @{ File = '.agents/plugins/marketplace.json'; Field = 'codex' }
    ) {
        $marketplace = Read-Json (Join-Path -Path $REPO_ROOT -ChildPath $File)
        $entry       = $marketplace.plugins | Where-Object { $_.name -EQ 'unwire' }

        $marketplace.name | Should -Be 'claude-unwire'
        $path = $Field -EQ 'codex' ? $entry.source.path : $entry.source
        $path | Should -Be './plugins/unwire'
    }
}

Describe 'skills' {
    It 'skill_names: every skill folder has a SKILL.md named after the folder' {
        $SkillFiles.Count | Should -BeGreaterThan 0

        foreach ($file in $SkillFiles) {
            $folderName = Split-Path -Path (Split-Path -Path $file -Parent) -Leaf
            $content    = Get-Content -Path $file -Raw

            $content | Should -Match "(?m)^name: $folderName\r?$"
            $content | Should -Match '(?m)^description: \S'
        }
    }

    It 'outside_claude: every SKILL.md with Claude-only names points at the explanation' {
        foreach ($file in $SkillFiles) {
            $content = Get-Content -Path $file -Raw
            if ($content -NOTMATCH 'CLAUDE_PLUGIN_ROOT|AskUserQuestion') {
                continue
            }
            $content | Should -BeLike '*Outside Claude*Code*' -Because "$file uses Claude-only names"
        }
    }
}
