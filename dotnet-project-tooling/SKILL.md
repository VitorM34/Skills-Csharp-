---
name: dotnet-project-tooling
description: Configurar e revisar a estrutura de projetos/soluções .NET - project SDKs (Microsoft.NET.Sdk/Web/Worker), csproj, propriedades MSBuild, Directory.Build.props/targets, Central Package Management (Directory.Packages.props), global.json (versão do SDK, rollForward), analyzers (CA/IDE), .editorconfig/.globalconfig, severidade, EnforceCodeStyleInBuild, TreatWarningsAsErrors, dotnet format, ContinuousIntegrationBuild, política de suporte/versões do .NET. Use quando o usuário pedir organizar a solution, padronizar build/pacotes, travar versão do SDK, configurar analyzers/CI ou revisar csproj. Based on official Microsoft Learn docs (.NET 10 SDK, NuGet).
---

# Tooling de projeto .NET (SDK, MSBuild, pacotes, analyzers)

Só afirmar o que a doc oficial diz (fontes no fim). Convenções de código: `csharp-coding-conventions`. Nullable: `csharp-nullable-references`. Testes/CI: `dotnet-test-automation`. Deploy: `aspnet-hosting-deployment`.

## Project SDKs
`<Project Sdk="...">` define conjuntos de targets/tasks: `Microsoft.NET.Sdk` (base), **`Microsoft.NET.Sdk.Web`** (ASP.NET Core; depende de .NET SDK + Razor SDK), `Microsoft.NET.Sdk.Razor`, `Microsoft.NET.Sdk.BlazorWebAssembly`, `Microsoft.NET.Sdk.Worker`, `Aspire.AppHost.Sdk`, `MSTest.Sdk`. Os outros SDKs herdam as propriedades do .NET SDK. Projetos .NET são MSBuild XML (`.csproj`). `ImplicitUsings` (`enable`) adiciona `global using` conforme o SDK (templates .NET 6+ já habilitam).

## Directory.Build.props / .targets
- Arquivos na raiz que se aplicam a **todos os projetos na pasta e subpastas**. **`Directory.Build.props` é importado cedo** (por `Microsoft.Common.props`): bom para definir **propriedades padrão**; **não referencie propriedades definidas depois** (avaliam vazio). **`Directory.Build.targets` é importado tarde**: para targets e para propriedades que dependem do projeto/pacotes. Exemplo oficial de uso: habilitar `EnforceCodeStyleInBuild` e `TreatWarningsAsErrors` para todos os projetos.
- O MSBuild sobe a árvore a partir do projeto e **para no primeiro** `Directory.Build.props` encontrado (a localização da solution é irrelevante); para herdar de um pai, importe-o explicitamente. **Linux é case-sensitive**: o nome precisa ser exatamente `Directory.Build.props`.

## Central Package Management (NuGet)
- Crie `Directory.Packages.props` na raiz com `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` e `<PackageVersion Include="X" Version="..." />`; nos `.csproj`, **`<PackageReference Include="X" />` sem `Version`**. (`dotnet new packagesprops` gera o arquivo.)
- **Só um `Directory.Packages.props` é avaliado por projeto** (o mais próximo); para herdar do pai, **importe manualmente** (`GetPathOfFileAbove`).
- Versões por TFM via `Condition`. **Transitive pinning** (`CentralPackageTransitivePinningEnabled`): promove dependência transitiva; **downgrade não é permitido** (NU1109) e, em **bibliotecas**, o pack promove os pinados a dependências explícitas — avalie com cuidado. **`VersionOverride`** no `PackageReference` sobrepõe a versão central; desabilite com `CentralPackageVersionOverrideEnabled=false`. **`GlobalPackageReference`** (no `Directory.Packages.props`) aplica um pacote a **todos** os projetos (analyzers/versionamento), com `PrivateAssets=All`/IncludeAssets de desenvolvimento (SDK 7+/NuGet 6.4+). Desabilite por projeto com `ManagePackageVersionsCentrally=false`.

## global.json (versão do SDK)
- Define **qual SDK** os comandos usam (independente do runtime alvo do projeto). Sem `global.json`, usa-se o SDK mais recente instalado; **em CI normalmente se define uma faixa aceitável** com `rollForward`.
- `"sdk": { "version": "10.0.100", "rollForward": "latestFeature" }`: `version` exige **número completo** (sem curingas/ranges); `rollForward`: `patch`, `feature`, `minor`, `major`, `latestPatch`, `latestFeature`, `latestMinor`, `latestMajor`, **`disable`** (exato; **use com package lock files**); `allowPrerelease`; `paths` (SDK 10+). A busca sobe os diretórios (CLI a partir do diretório atual; resolver MSBuild a partir da solution/projeto).
- **Feature bands:** `x.y.znn` (z = banda, nn = patch); SDK 9.0.101 e 9.0.201 são bandas diferentes.

## Analyzers e estilo de código
- **Analyzers Roslyn vêm no SDK** (não precisa instalar); **habilitados por padrão em projetos .NET 5+** (`EnableNETAnalyzers` para outros alvos). Diagnósticos **`CAxxxx`** (qualidade: segurança, desempenho, design) e **`IDExxxx`** (estilo). Só **parte** das regras vem ligada por padrão (alguns como erro/aviso, outras como sugestão).
- **`AnalysisMode`** (`Recommended`, etc.) e `AnalysisMode<Category>` habilitam conjuntos maiores; ⚠ se configurar por propriedade MSBuild, **configurações em massa do .editorconfig são ignoradas**. `AnalysisLevel` fixa o conjunto por versão.
- **Severidade** (`.editorconfig`/`.globalconfig`): `dotnet_diagnostic.<ID>.severity = error|warning|suggestion|silent|none|default` (regra única) e `dotnet_analyzer_diagnostic.category-<cat>.severity` (categoria; só afeta regras **já habilitadas** por padrão). `error` quebra o build; `warning` só com warnaserror.
- **`.editorconfig`**: opções por arquivo/pasta (`[*.cs]`, `root = true`), vale no build e no IDE; só para arquivos **source**. **Global AnalyzerConfig** (`.globalconfig`, `is_global = true`, sem seções): opções de **projeto inteiro**, incluindo `AdditionalFiles`; pode ser incluído condicionalmente (ex.: relaxar regras em projetos de teste) via item `GlobalAnalyzerConfigFiles`.
- **Estilo (IDE...) não é verificado no build por padrão:** ligue **`EnforceCodeStyleInBuild=true`** (aplica as regras configuradas como warning/error; algumas só rodam no VS). **`TreatWarningsAsErrors`**; `CodeAnalysisTreatWarningsAsErrors=false` permite manter avisos CA como avisos com `-warnaserror`. Código **gerado** é ignorado (`generated_code = true` para padrões extras).
- **`dotnet format`** formata conforme `.editorconfig`; **`--verify-no-changes`** falha se algo precisa mudar (útil em CI).
- **`ContinuousIntegrationBuild=true`** em CI (ex.: condicionar por `TF_BUILD`): habilita configurações de build oficial/determinístico (caminhos armazenados não locais).
- Em testes/CI, builds implícitos do VS pulam análise, mas só são otimizados se `TreatWarningsAsErrors` não for `true` (`OptimizeImplicitlyTriggeredBuild`).

## Suporte e versões do .NET
.NET 10 = **LTS** (suporte até **nov/2028**); .NET 9 = STS (até nov/2026); .NET 8 = LTS (até nov/2026). Major pode ter breaking changes; patches mensais (patch Tuesday = 2ª terça); apps usam o **patch mais recente instalado** do major.minor alvo e **não** sobem de major automaticamente. Cheque a política oficial antes de decidir TFM.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Versões de pacote espalhadas em vários `.csproj` (usar CPM) | Média |
| 2 | `Directory.Build.props` referenciando propriedades tardias; nome com caixa errada (Linux) | Média |
| 3 | Sem `global.json` em repo/CI (SDK muda sem aviso) ou `version` com curinga | Média |
| 4 | `rollForward` ≠ `disable` combinado com package lock files | Baixa |
| 5 | Warnings ignorados: sem `TreatWarningsAsErrors`/severidade `error` em regras críticas | Média |
| 6 | Estilo configurado no `.editorconfig` mas sem `EnforceCodeStyleInBuild`/`dotnet format --verify-no-changes` no CI | Média |
| 7 | `AnalysisMode` por propriedade anulando configuração em massa do `.editorconfig` | Baixa |
| 8 | Supressões (`#pragma`, `none`) sem justificativa; regras desligadas globalmente em vez de por projeto de teste | Média |
| 9 | Transitive pinning/`VersionOverride` em biblioteca sem avaliar efeito no pack | Média |
| 10 | Alvo em versão fora de suporte | Alta |

## Fontes oficiais
- Project SDKs: https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview
- MSBuild properties: https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props
- Customize build by folder: https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory
- Central Package Management: https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management
- global.json: https://learn.microsoft.com/en-us/dotnet/core/tools/global-json
- Code analysis overview: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview
- Analysis configuration options: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options
- Configuration files: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files
- dotnet format: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format
- Releases and support: https://learn.microsoft.com/en-us/dotnet/core/releases-and-support
