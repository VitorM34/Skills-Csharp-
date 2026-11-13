---
name: dotnet-ci-cd
description: Projetar e revisar pipelines CI/CD para .NET (exemplo em GitHub Actions) - restore determinístico (lock files, --locked-mode, global.json), build com analyzers e warnings como erro, dotnet format --verify-no-changes, dotnet test (VSTest/MTP, trx, cobertura, exit codes), NuGet Audit, publicação de containers (dotnet publish /t:PublishContainer ou Dockerfile), pack/push de NuGet, aplicação de migrations do EF Core (bundle, script idempotente, has-pending-model-changes), e segurança do pipeline (GITHUB_TOKEN, secrets, pin de actions, OIDC, script injection, cache). Use quando o usuário pedir criar/revisar workflow de CI, deploy, pipeline de release ou "como aplico migrations no deploy". Fontes - Microsoft Learn (.NET, EF, NuGet) e docs do GitHub (externa, para sintaxe do Actions).
---

# CI/CD para .NET

**Proveniência:** comandos e comportamentos de **.NET/EF/NuGet** vêm da Microsoft Learn; a **sintaxe e a segurança do GitHub Actions** vêm da documentação do GitHub (fonte **externa**, marcada **[GH]**). **Não pesquisei Azure DevOps, GitLab nem outros CIs**: os comandos `dotnet` valem em qualquer um, mas a sintaxe do pipeline você precisa confirmar na doc do seu CI. A **ordem das etapas e os gates são CONVENÇÃO**. Ligações: `dotnet-project-tooling`, `dotnet-test-automation`, `efcore-migrations-modeling`, `aspnet-hosting-deployment`, `dotnet-security-review`, `dotnet-version-migration`.

## 1. Restore determinístico (mesma entrada ⇒ mesmos pacotes)
- **Lock file** (NuGet): `RestorePackagesWithLockFile=true` gera `packages.lock.json` (fecho completo, inclusive transitivas). Em CI use **locked mode**: `dotnet restore --locked-mode` (ou `RestoreLockedMode=true`) — restaura **exatamente** o que está no lock file e **falha** se as dependências do projeto mudaram depois. Motivo oficial: versões flutuantes (`4.*`), publicação de versão nova que casa o intervalo, ou pacote removido do feed alteram o grafo sem você mudar nada. Commite o `packages.lock.json`.
- **SDK fixo:** `global.json` (`dotnet-project-tooling`). A doc de NuGet avisa que **pacotes implícitos adicionados pelo SDK mudam com a versão do SDK**, quebrando o locked mode; mitigação oficial: `rollForward` = **`disable`** (todos os devs e o CI usam o mesmo SDK).
- **Fontes confiáveis:** `nuget.config` na raiz com `<clear />`; Package Source Mapping; saber de qual feed vem cada pacote (Dependency Confusion) — ver `dotnet-security-review`.
- **NuGet Audit** roda no restore e emite **NU1901–NU1904**; em projetos `net10.0` audita também transitivas (`NuGetAuditMode=all`). Para falhar o build use warnings-as-errors (`dotnet-project-tooling`). Defina `auditSources` se o CI não usa nuget.org como fonte de pacotes.

## 2. Build e qualidade
- `dotnet build --no-restore -c Release`. **`ContinuousIntegrationBuild=true`** em CI (a doc mostra condicionar pela variável do CI: `GITHUB_ACTIONS` no GitHub, `TF_BUILD` no Azure Pipelines) — normaliza caminhos armazenados (build "oficial"); **não** ligue localmente (o debugger não acha os fontes).
- **Analyzers como gate:** `TreatWarningsAsErrors`/severidade `error` (regras que você escolher), `EnforceCodeStyleInBuild=true` (estilo IDE só roda no build com isso), `AnalysisModeSecurity` (regras de segurança vêm desligadas por padrão — ver `dotnet-security-review`).
- **`dotnet format --verify-no-changes`**: sai com erro se o código não segue o `.editorconfig`.

## 3. Testes
- Fluxo da doc [GH]: `dotnet restore` → `dotnet build --no-restore` → `dotnet test --no-build`. `--logger trx --results-directory <dir>` (VSTest) gera relatório; **suba os resultados como artefato com `if: always()`** para existir mesmo quando há falha.
- **Runner (SDK 10):** `dotnet test` usa VSTest por padrão; para **Microsoft.Testing.Platform (MTP)** configure no `global.json`: `"test": { "runner": "Microsoft.Testing.Platform" }`. Com MTP **todos** os projetos de teste devem ser MTP (senão erro) e as opções dependem das **extensões registradas** no projeto (opção desconhecida ⇒ exit code **5**). `--no-build` implica `--no-restore` (mantenha `obj` e o cache de pacotes). `dotnet test --help` mostra o que a sua versão aceita. Detalhes e frameworks: `dotnet-test-automation`.
- **Exit codes do MTP** (úteis para CI): `0` sucesso; `2` pelo menos um teste falhou; `3` sessão abortada; `5` argumentos inválidos; `7` sessão falhou/crashou; `8` nenhum teste descoberto (ou todos pulados em política estrita); `9` menos testes que `--minimum-expected-tests`; `10` falha de infraestrutura do adapter/fixture. **Use `--minimum-expected-tests`** para o CI falhar se os testes "sumirem". ⚠ Parte do tratamento de "zero testes na execução inteira" exige **SDK .NET 11**; confira na sua versão.
- **Cobertura:** Coverlet (collector ou MSBuild) + ReportGenerator, ou o coletor interno (`.coverage` binário, converter com `dotnet-coverage`) — ver `dotnet-test-automation`.
- Testes de integração com banco real precisam de serviços no CI (containers/serviço do runner): ver `efcore-testing`, `dotnet-integration-testing`.

## 4. Empacotar e publicar
- **Container sem Dockerfile:** `dotnet publish --os linux --arch x64 /t:PublishContainer -p ContainerRegistry=<registry>` (SDK ≥ 8.0.200 já inclui; **não precisa de Docker/Podman** para publicar em registry ou gerar tarball; Docker só para rodar local). `-p ContainerArchiveOutputPath=./images/img.tar.gz` gera **tarball** — a doc cita o uso em organizações que **escaneiam** a imagem antes. Propriedades: `ContainerRepository`, `ContainerImageTag`, `ContainerFamily`, `ContainerUser` (padrão **não-root `app`** em imagens Microsoft .NET 8+). **Autenticação em registry** via `docker login` (arquivo `~/.docker/config.json`, ou `DOCKER_CONFIG`). `-bl` gera binlog para diagnosticar. Alternativa: Dockerfile multi-stage `sdk` → `aspnet` (`aspnet-hosting-deployment`).
- **NuGet:** `dotnet pack -c Release` → `dotnet nuget push <pkg>.nupkg` (exemplo oficial [GH] publica no GitHub Packages com `permissions: packages: write` e `NUGET_AUTH_TOKEN`).
- Evite rebuild entre etapas: gere o artefato **uma vez** e promova o mesmo artefato entre ambientes (CONVENÇÃO).

## 5. Migrations do EF Core no deploy (oficial: *Applying Migrations*)
| Estratégia | Quando | Observações oficiais |
|---|---|---|
| **Migration bundle** | **deploy automatizado** | executável gerado **no CI** (`dotnet ef migrations bundle --self-contained --target-runtime linux-x64 --output artifacts/efbundle`), roda **sem SDK/EF tools/código-fonte**; usa **lock de migrations** e roda `UseSeeding`; `--connection` para o alvo; **não** permite inspecionar o SQL. |
| **Script SQL** | revisão por DBA / deploy com gate | `dotnet ef migrations script --idempotent --output artifacts/migrations.sql`; **idempotente** verifica o histórico e aplica só o que falta (depende do provider; SQLite não suporta); rollback = script com `from` mais novo que `to` (**cuidado: perda de dados**). |
| `dotnet ef database update` | só desenvolvimento/teste | exige SDK e fontes no servidor; aplica sem revisão. |
| `MigrateAsync()` no startup | só se aceitar os trade-offs | EF 9+ tem **lock no banco**, mas o app precisa de permissão de schema; sem revisão; rollback difícil. |
- **Sempre inspecione e teste a migration antes de produção** (pode dropar coluna quando a intenção era renomear). **Use identidade separada para deploy de schema** (com permissão de alterar schema); a do app em runtime só leitura/escrita de dados. Crie o banco pela infraestrutura/DBA; o script só atualiza.
- **Gate de CI oficial:** `dotnet ef migrations has-pending-model-changes` (EF 8+) falha quando alguém esqueceu de criar a migration; alternativa em teste: `context.Database.HasPendingModelChanges()`. No EF 9+, `Migrate()` lança exceção com mudanças pendentes. Projeto multi-target no EF 10 exige `--framework`.
- Ferramentas locais: `dotnet tool restore` + manifesto (`dotnet-ef` versionado) mantém o CI repetível (ver `dotnet-project-tooling`).

## 6. Segurança do pipeline [GH]
- **`GITHUB_TOKEN`:** mínimo necessário; boa prática = padrão **somente leitura** do conteúdo e elevar por job (`permissions:`). Qualquer um com escrita no repo lê os secrets ⇒ credenciais com **menor privilégio**.
- **Secrets:** nunca em texto no workflow; redaction **não é garantida** (valores transformados/estruturados escapam) — não use JSON/YAML como secret, registre valores derivados, **gire** secrets e apague logs expostos; **Environments com revisores obrigatórios** protegem secrets de deploy.
- **OIDC:** em vez de guardar credenciais de nuvem de longa duração como secret, estabeleça confiança OIDC com o provedor e peça **token de curta duração por job** (`permissions: id-token: write`); cuidado com a claim `sub` para só permitir workflows previstos.
- **Script injection:** não interpole `${{ github.event.* }}` direto em `run:`; use **variável de ambiente intermediária** (ou uma action que receba o valor como argumento).
- **Actions de terceiros:** podem acessar secrets/`GITHUB_TOKEN`; **fixe em SHA de commit completo** (o GitHub também oferece *workflow dependency lockfiles*, descrito como a proteção mais forte), audite o código, mantenha atualizadas (Dependabot). Fixar por tag só se confiar no autor.
- **PRs não confiáveis:** evite `pull_request_target`/`workflow_run` com checkout de código do PR (workflows privilegiados + cache da branch principal = risco "pwn request").
- **Cache:** `actions/setup-dotnet` com `cache: true` exige `packages.lock.json` (falha sem ele) e `cache-dependency-path`; **não guarde segredos em caminhos de cache** — qualquer um com leitura pode abrir PR e acessar o cache (inclusive forks na branch base). Para poucos pacotes o cache pode nem ajudar.

## 7. Exemplo mínimo (GitHub Actions) — adaptado dos exemplos oficiais [GH]/Microsoft
```yaml
name: ci
on:
  pull_request:
  push:
    branches: [ main ]
permissions:
  contents: read              # menor privilégio; eleve por job se precisar
jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<SHA-completo>        # fixe por SHA (resolva o SHA da versão desejada)
      - uses: actions/setup-dotnet@<SHA-completo>
        with:
          dotnet-version: '10.0.x'                   # mantenha igual ao global.json
          cache: true
          cache-dependency-path: '**/packages.lock.json'
      - run: dotnet restore --locked-mode
      - run: dotnet format --verify-no-changes --no-restore
      - run: dotnet build --no-restore -c Release -p:ContinuousIntegrationBuild=true -warnaserror
      - run: dotnet test --no-build -c Release --logger trx --results-directory TestResults
      - uses: actions/upload-artifact@<SHA-completo>
        if: ${{ always() }}
        with:
          name: test-results
          path: TestResults
      # gate de EF (se usar migrations): dotnet tool restore && dotnet ef migrations has-pending-model-changes
```
> `dotnet-version` (com sintaxe `10.0.x`), `cache`/`cache-dependency-path`, `--locked-mode` e `--logger trx` vêm dos exemplos oficiais; `-warnaserror` é citado na doc de MSBuild. Existe também a opção de ler a versão do `global.json` na action, mas **não foi verificada nas páginas lidas**: confirme na doc da `setup-dotnet`. O exemplo omite deploy: faça job separado (needs: build-test), com **Environment**, OIDC e o artefato (bundle/script/imagem) gerado no build.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Restore sem lock file/`--locked-mode`; versões flutuantes; `global.json` ausente ou sem `rollForward: disable` quando há lock files | Média |
| 2 | Pipeline que aplica migrations com `database update`/`MigrateAsync()` direto em produção, sem revisar SQL e sem identidade separada | Alta |
| 3 | Sem gate `has-pending-model-changes` / migration não commitada | Média |
| 4 | Secrets em texto, `GITHUB_TOKEN` com permissões amplas, cloud credentials de longa duração (em vez de OIDC) | Alta |
| 5 | `run:` interpolando `github.event.*`; actions de terceiros por tag mutável; `pull_request_target` com checkout do PR | Alta |
| 6 | Testes que "passam" com zero testes (sem `--minimum-expected-tests`/verificação); resultados não publicados quando falham | Média |
| 7 | NuGet Audit/NU190x ignorados; `nuget.config` sem `<clear />`/source mapping | Média |
| 8 | Rebuild diferente por ambiente (artefato não promovido); imagem sem scan; container como root | Média |
| 9 | `ContinuousIntegrationBuild` ligado também localmente | Baixa |
| 10 | Cache contendo segredos; cache sem lock file (falha) | Média |
| 11 | Pipeline em outro CI (Azure DevOps/GitLab) escrito "de cabeça" — **sem doc lida**: confirme a sintaxe na doc do CI | Verificar |

## Fontes
**Microsoft Learn**
- Locking dependencies (NuGet): https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#locking-dependencies
- NuGet Audit: https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages
- Segurança da cadeia NuGet: https://learn.microsoft.com/en-us/nuget/concepts/security-best-practices
- global.json: https://learn.microsoft.com/en-us/dotnet/core/tools/global-json
- MSBuild properties (`ContinuousIntegrationBuild`): https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props
- dotnet test (MTP): https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test-mtp
- dotnet test (visão geral): https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test
- MTP troubleshooting (exit codes): https://learn.microsoft.com/en-us/dotnet/core/testing/microsoft-testing-platform-troubleshooting
- Code coverage: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-code-coverage
- dotnet format: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format
- Containers com `dotnet publish`: https://learn.microsoft.com/en-us/dotnet/core/containers/sdk-publish
- Referência de propriedades de container: https://learn.microsoft.com/en-us/dotnet/core/containers/publish-configuration
- EF Core — Applying Migrations: https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying
- EF Core — Managing Migrations (pending model changes): https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/managing
- EF Core CLI: https://learn.microsoft.com/en-us/ef/core/cli/dotnet
**GitHub (externa)**
- Building and testing .NET: https://docs.github.com/en/actions/tutorials/build-and-test-code/net
- Secure use reference: https://docs.github.com/en/actions/reference/security/secure-use
- OpenID Connect: https://docs.github.com/en/actions/concepts/security/openid-connect
- Dependency caching: https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching
