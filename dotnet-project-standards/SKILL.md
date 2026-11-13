---
name: dotnet-project-standards
description: Padrão base para criar e organizar um projeto/repositório .NET do zero - comandos dotnet new (sln/slnx, global.json, .editorconfig, .gitignore, Directory.Build.props, nuget.config, tool-manifest, projetos web/classlib/worker/testes), layout src/tests, arquivos de raiz e seus papéis, defaults de csproj (Nullable, TFM, analyzers), segredos de dev, e como preparar o repositório para o Claude Code (CLAUDE.md, rules, skills do projeto). Use quando o usuário pedir "iniciar um projeto .NET", "estrutura padrão da solution", "o que ter na raiz do repo", "criar CLAUDE.md do projeto" ou padronizar vários projetos. Based on Microsoft Learn (dotnet new, global.json, Directory.Build.props, artifacts output, solution format) e documentação oficial do Claude Code (memória/CLAUDE.md). Layout de pastas é convenção.
---

# Padrão de projeto e de repositório .NET

**Proveniência:** **[MS]** Microsoft Learn (templates do `dotnet new`, `global.json`, `Directory.Build.props`, *Artifacts output layout*, formato de solution, tutorial de testes); **[CC]** documentação oficial do **Claude Code** (*How Claude remembers your project*); **CONVENÇÃO** = escolha minha (a Microsoft não prescreve um layout de pastas). Esta skill é um **ponto de partida**: **siga a estrutura que o projeto já tem** (convenções locais vencem).
Ligações: `dotnet-project-tooling` (detalhes de MSBuild/CPM/analyzers), `dotnet-clean-architecture`, `dotnet-modular-monolith`, `dotnet-feature-workflow` (depois do bootstrap), `dotnet-ci-cd`, `dotnet-test-automation`, `aspnet-configuration-options`, `dotnet-local-dev-containers`, `csharp-coding-conventions`.

## Passo 0 — Perguntas antes de gerar
Tipo de app (API Minimal/controllers, Razor/Blazor, worker, gRPC, biblioteca), **arquitetura** (projeto único × camadas × módulos — `dotnet-clean-architecture`/`dotnet-modular-monolith`), framework de teste (xUnit/MSTest/NUnit), banco/infra, e se vai rodar em container. **Não invente arquitetura**: para app pequeno um projeto único é válido; evolua para vários quando precisar de fronteiras (`dotnet-clean-architecture`).

## Bootstrap por comandos [MS]
```bash
mkdir MeuApp && cd MeuApp && git init
dotnet new globaljson --sdk-version <versão-do-SDK-instalado> --roll-forward latestFeature   # --test-runner MTP (SDK 10+) opcional
dotnet new gitignore
dotnet new editorconfig                     # --empty para um arquivo vazio
dotnet new buildprops --use-artifacts       # Directory.Build.props + layout de saída "artifacts" (.NET 8+)
dotnet new nugetconfig
dotnet new tool-manifest                    # ferramentas locais (ex.: dotnet-ef) versionadas no repo
dotnet new sln -n MeuApp                    # .NET 10: formato .slnx por padrão; --format sln|slnx (SDK 9.0.200+)
dotnet new webapi -n MeuApp.Api -o src/MeuApp.Api        # ou webapiaot / web / mvc / grpc / worker / blazor ...
dotnet new classlib -n MeuApp.Application -o src/MeuApp.Application
dotnet new xunit -n MeuApp.Tests -o tests/MeuApp.Tests    # ou mstest / nunit
dotnet sln add src/MeuApp.Api tests/MeuApp.Tests          # (o dotnet sln encontra o único .sln/.slnx da pasta)
dotnet add tests/MeuApp.Tests reference src/MeuApp.Api
```
- **Templates padrão** (SDK): `webapi`, `webapiaot`, `apicontroller`, `web` (vazio), `mvc`, `webapp` (Razor Pages), `grpc`, `blazor`, `blazorwasm`, `classlib`, `console`, `worker`, `razorclasslib`, `xunit`, `mstest`, `nunit`, e de configuração: `buildprops`, `buildtargets`, `editorconfig`, `globaljson`, `gitignore`, `nugetconfig`, `tool-manifest`, `sln`. Liste os da sua máquina com `dotnet new list`.
- `dotnet new packagesprops` (Central Package Management) é citado pela doc do **NuGet**, mas **não aparece na tabela de templates padrão do SDK** que li: confirme com `dotnet new list`; se faltar, crie o `Directory.Packages.props` à mão (`dotnet-project-tooling`).
- **`global.json`:** `version` precisa ser **completo** (sem curingas); com *package lock files* use `rollForward: disable` (`dotnet-ci-cd`).
- **Solution `.slnx`:** a partir do .NET 10 é o padrão de `dotnet new sln`; `dotnet sln migrate` converte um `.sln` existente para `.slnx`; filtros de solução `.slnf` (`dotnet new slnf` a partir do .NET 11). Confira a compatibilidade da sua IDE/CI antes de migrar.
- **Convenção do tutorial oficial de testes [MS]:** biblioteca `PrimeService` + projeto de teste `PrimeService.Tests`, criados com `dotnet new sln`, `dotnet sln add`, `dotnet new xunit`. **Mantenha testes unitários em projeto separado dos de integração** (a doc de boas práticas diz que isso evita dependências de infraestrutura nos unitários).

## Layout (CONVENÇÃO)
```
repo/
├─ src/               MeuApp.Api · MeuApp.Application · MeuApp.Domain · MeuApp.Infrastructure
├─ tests/             MeuApp.UnitTests · MeuApp.IntegrationTests
├─ artifacts/         (gerado: bin/obj/publish/package — fora do git)
├─ global.json · Directory.Build.props · Directory.Packages.props · .editorconfig · nuget.config
├─ .gitignore · .config/dotnet-tools.json · MeuApp.slnx
├─ docker-compose.yml (dev) · Dockerfile · .github/workflows/ (CI)
├─ README.md · CLAUDE.md · .claude/ (skills/rules do projeto)
```
- Nome do projeto = namespace raiz; `X.Tests` para testes do projeto `X` (padrão do tutorial oficial). Camadas e dependências: `dotnet-clean-architecture`; módulos: `dotnet-modular-monolith`.
- **Artifacts output layout [MS]** (`UseArtifactsOutput=true`, .NET 8+): todos os `bin/`, `obj/`, `publish/` e `package/` vão para `artifacts/<tipo>/<projeto>/<pivot>` ao lado do `Directory.Build.props` (ex.: `artifacts/bin/MyApp/debug`, `artifacts/publish/MyApp/release_linux-x64`, `artifacts/package/release`); personalize com `ArtifactsPath`/`ArtifactsProjectName`/`ArtifactsPivots`; **inclua `artifacts/` no `.gitignore`**.

## Arquivos de raiz e papel [MS]
| Arquivo | Papel | Skill |
|---|---|---|
| `global.json` | fixa o **SDK** (e runner de teste) | `dotnet-project-tooling` |
| `Directory.Build.props` | propriedades comuns a **todos** os projetos (`Nullable`, `ImplicitUsings`, `TreatWarningsAsErrors`, `EnforceCodeStyleInBuild`, `AnalysisMode...`, `ContinuousIntegrationBuild` condicional por CI, `UseArtifactsOutput`); **não herda do pai** (use `--inherit` do template) | idem |
| `Directory.Packages.props` | versões **centralizadas** de pacotes (CPM) | idem |
| `.editorconfig` | estilo e severidade de analyzers | `csharp-coding-conventions` |
| `nuget.config` | fontes (`<clear />`), source mapping | `dotnet-security-review` |
| `.config/dotnet-tools.json` | ferramentas locais versionadas (`dotnet tool restore`) | `dotnet-ci-cd` |
| `.gitignore` | `bin/obj/artifacts`, segredos locais | — |
- **Defaults de projeto:** `TargetFramework` = versão LTS suportada (`dotnet-version-migration`); `Nullable=enable` e `ImplicitUsings=enable` (os templates atuais já habilitam); analyzers do SDK ligados; `TreatWarningsAsErrors` no CI.
- **Segredos e configuração:** nunca no repositório; `dotnet user-secrets init` (cria `UserSecretsId`) **só para desenvolvimento**; `appsettings.json` + `appsettings.{Environment}.json`; `launchSettings.json` é **só dev**; produção via Key Vault/variáveis (`aspnet-configuration-options`, `dotnet-security-review`).
- **Ambiente local:** `docker-compose` com banco/Redis/RabbitMQ/Seq (`dotnet-local-dev-containers`); README com "como rodar" em 3 comandos.

## Preparar o repositório para o Claude Code [CC]
- **O que é:** cada sessão começa com **contexto novo**; dois mecanismos persistem conhecimento: **`CLAUDE.md`** (instruções que você escreve) e **auto memory** (notas do Claude). O `CLAUDE.md` é **contexto, não configuração imposta** — para **bloquear** uma ação use um **hook PreToolUse**.
- **Onde:** `./CLAUDE.md` ou `./.claude/CLAUDE.md` (compartilhado no git); `~/.claude/CLAUDE.md` (pessoal); **`./CLAUDE.local.md`** (pessoal do projeto — **coloque no `.gitignore`**); política gerenciada (organização). Subdiretórios carregam sob demanda. Repositórios com `AGENTS.md` podem usá-lo. **`/init`** gera um `CLAUDE.md` inicial (comandos de build/teste, convenções); refine com o que o Claude **não descobre sozinho**.
- **Como escrever bem:** fatos que valem **toda sessão** (comandos de build/teste, convenções, layout, regras "sempre faça X"); **concreto e verificável** ("rode `dotnet test` antes de commitar", "handlers ficam em `src/Api/Endpoints`"); **abaixo de ~200 linhas**; organizado por cabeçalhos; **sem instruções contraditórias**. **Procedimento de vários passos ou assunto de uma parte do código ⇒ skill ou regra por caminho** (`.claude/rules/`), não `CLAUDE.md`. Importe arquivos com `@caminho` (máx. 4 níveis; importar **não reduz** o custo de contexto). Audite com `/doctor prompt-audit` (cobre CLAUDE.md, rules, skills etc.).
- **Skills do projeto:** instale as skills deste conjunto **no projeto** (`./install.sh /caminho/projeto` → `<projeto>/.claude/skills`) ou no usuário (`~/.claude/skills`).
- **Modelo de `CLAUDE.md` para .NET (adapte; mantenha curto):**
```markdown
# <NomeDoApp>
## Comandos
- Restaurar/compilar: `dotnet restore --locked-mode` · `dotnet build --no-restore -c Release`
- Testar: `dotnet test --no-build -c Release` (unit em tests/*.UnitTests; integração exige Docker: `docker compose up -d`)
- Formatar: `dotnet format --verify-no-changes`
- Migrations: `dotnet ef migrations add <Nome> -p src/<Infra> -s src/<Api>` (revisar o SQL; nunca editar migration aplicada)
## Arquitetura
- src/<App>.Domain (sem dependências) → Application → Infrastructure/Api. Regra de dependência: <resumo>. Módulos: <lista>.
## Convenções
- C# 14 / .NET 10, Nullable ligado, sem warnings novos. Endpoints: Minimal API com MapGroup + TypedResults.
- DTOs nunca expõem entidades; validação no servidor; ProblemDetails para erros.
- Segredos: nunca no repo (user-secrets em dev).
## Skills e quando usar
- Nova funcionalidade → `dotnet-feature-workflow`; revisão → `dotnet-review-all`; segurança → `dotnet-security-review`.
```

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Sem `global.json` ou sem `.editorconfig`/`Directory.Build.props` na raiz (cada projeto configurado de um jeito) | Média |
| 2 | `bin/`, `obj/`, `artifacts/`, `*.user`, segredos ou `appsettings.*.local` versionados; `.gitignore` ausente | Alta |
| 3 | Segredos/connection strings de produção no repositório ou em `appsettings.json` | Alta |
| 4 | Testes unitários e de integração no mesmo projeto; projeto de teste sem referência clara ao projeto testado | Baixa |
| 5 | Camadas/pastas que não refletem a regra de dependência (Domain referenciando Infrastructure) | Média |
| 6 | Versões de pacote espalhadas (sem CPM) em solução com vários projetos | Baixa |
| 7 | Solution em `.slnx` sem checar suporte da IDE/CI da equipe | Baixa |
| 8 | `CLAUDE.md` gigante, vago ("formate direito"), contraditório ou com procedimentos que deveriam ser skills; `CLAUDE.local.md` fora do `.gitignore` | Média |
| 9 | Regra crítica só no `CLAUDE.md` quando precisa ser **imposta** (use hook/CI) | Média |
| 10 | README sem "como rodar/testar"; sem docker-compose de dev para dependências | Baixa |

## Fontes
**[MS]** Templates `dotnet new` padrão: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-new-sdk-templates · `dotnet sln`: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-sln · `global.json`: https://learn.microsoft.com/en-us/dotnet/core/tools/global-json · Artifacts output layout: https://learn.microsoft.com/en-us/dotnet/core/sdk/artifacts-output · MSBuild properties: https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props · Customize build by folder: https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory · Central Package Management: https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management · Tutorial de testes xUnit: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-csharp-with-xunit · Boas práticas de teste: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices · Secrets em dev: https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets
**[CC]** Claude Code — How Claude remembers your project (CLAUDE.md, rules, auto memory): https://code.claude.com/docs/en/memory
