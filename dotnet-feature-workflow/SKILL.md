---
name: dotnet-feature-workflow
description: Fluxo de trabalho para implementar uma feature .NET/ASP.NET Core ponta a ponta (ex.: "criar CRUD de Pedidos", "adicionar endpoint X com banco") orquestrando as outras skills em ordem - descobrir o projeto, definir contrato (endpoints, DTOs, validação), modelo e persistência (EF Core + migration), service/interface/DI, endpoint (Minimal API ou controller), erros/auth/OpenAPI, testes (unit, integração, EF) e quality gates (analyzers, segurança, review). Use quando o usuário pedir para criar/adicionar uma funcionalidade completa, não apenas revisar um trecho. Esta skill não cria regras novas - delega às skills especialistas; a ordem é convenção, a escolha Minimal API × controllers e a sequência modelo→DbContext→endpoints→DTO vêm do tutorial oficial.
---

# Implementar uma feature ponta a ponta

**Proveniência:** esta skill **orquestra**; as regras técnicas vivem nas skills especialistas (todas baseadas na doc oficial). Do que é **oficial** aqui: (1) a recomendação *Minimal APIs para projetos novos, controllers em casos específicos* (doc *APIs overview*); (2) a sequência dos tutoriais oficiais (*Create a minimal API* / *controller-based web API*): projeto → pacotes → **model → DbContext → registrar contexto → endpoints (POST/GET/PUT/PATCH/DELETE) → DTO contra over-posting → teste**. A **ordem refinada abaixo e os gates são CONVENÇÃO** (marcados). Convenções locais do projeto vencem (`.editorconfig`, arquitetura existente).

## Passo 0 — Descobrir antes de escrever
Leia (não presuma): `*.csproj` (TFM, pacotes, `Nullable`), `Program.cs`, `appsettings*.json`, estrutura de pastas/projetos, um feature existente parecido, testes existentes, `Directory.Build.props`/`.editorconfig`. Identifique:
| Pergunta | Se já existe… | Se não existe |
|---|---|---|
| Estilo de API | **siga o existente** | **Minimal APIs** (oficial: recomendado para novos). **Controllers** se precisar de extensibilidade de model binding (`IModelBinder`/`IModelBinderProvider`), validação avançada (`IModelValidator`), application parts/application model ou OData — `aspnet-minimal-api` × `aspnet-controllers` |
| Arquitetura | camadas/módulos existentes (`dotnet-clean-architecture`, `dotnet-modular-monolith`) — **não cruze fronteiras** | simples e coesa; não introduza camadas novas sem pedido |
| Banco | provider/DbContext existente (`efcore-dbcontext-connection`) | pergunte o provider; segredos fora do código |
| Auth | esquema existente (`aspnet-authentication-authorization`) | pergunte quem acessa; **default = exigir autenticação** |
| API pública/versionada? | `aspnet-api-versioning` | só se houver consumidores externos |
Se houver ambiguidade que muda o desenho (provider, auth, síncrono × evento), **pergunte antes** de gerar muitos arquivos. Para features grandes, **apresente o plano (lista de arquivos e decisões) e peça confirmação**.

## Fluxo (CONVENÇÃO de ordem; cada fase delega)
### 1. Contrato primeiro
- Endpoints, verbos e status codes (`aspnet-http-endpoints`): POST→**201 + header `Location`** (`CreatedAtAction`), PUT/PATCH/DELETE→**204 No Content**, GET por id→200 ou **404** se não existir (todos conforme os tutoriais oficiais).
- **DTOs de entrada/saída** (`dotnet-dto-review`): o tutorial oficial introduz o DTO por último ("Prevent over-posting"), mas a doc diz que apps de produção limitam entrada/saída a um subconjunto do modelo (segurança, ocultar propriedades, reduzir payload) — por isso **defina o DTO já aqui**, nunca exponha a entidade.
- **Validação** (`aspnet-validation`; Minimal API exige `AddValidation()`), erros como `ProblemDetails` (`aspnet-error-handling`).
### 2. Modelo de domínio
`dotnet-model-review` (+ `csharp-nullable-references`, `csharp-modern-features`, `csharp-types-oop`). Se for DDD: `dotnet-ddd-tactical`.
### 3. Persistência
- Registrar/configurar o `DbContext` (`efcore-dbcontext-connection`), mapeamento e relacionamentos (`efcore-migrations-modeling`, `efcore-relationships-loading`, `efcore-advanced-mapping`).
- **Gerar a migration e revisar o SQL/diff** (`efcore-migrations-modeling`); lembrar: modelo com mudanças pendentes faz `Migrate()` lançar exceção no EF 9+ (`dotnet-version-migration`).
- Concorrência/transações quando houver escrita concorrente (`efcore-saving-concurrency`).
### 4. Camada de aplicação
- **Interface + service** (`dotnet-interface-review`, `dotnet-service-implementation`), **DI com lifetimes corretos** (`dotnet-dependency-injection`; `DbContext` é scoped), **async de ponta a ponta com `CancellationToken`** (`csharp-async-await`).
- Consultas: projeção/`AsNoTracking`/paginação (`efcore-querying`, `efcore-sql-performance`); mapeamento Entity↔DTO (`dotnet-object-mapping`, manual por padrão).
- Exceções: `dotnet-exception-handling`.
### 5. Camada HTTP
- Endpoints (`aspnet-minimal-api` com `MapGroup`/`TypedResults`, ou `aspnet-controllers` + `aspnet-mvc-controllers-filters`).
- **Autorização explícita** em cada endpoint (policy/role/`AllowAnonymous` consciente), **checando o dono do recurso** quando aplicável.
- OpenAPI (`aspnet-openapi`), versionamento se público (`aspnet-api-versioning`), cache/rate limit/timeouts se o caso pedir (`aspnet-caching`, `aspnet-rate-limiting`).
- Chamadas externas: `dotnet-httpclient-resilience`; eventos/filas: `dotnet-messaging` (outbox); jobs: `aspnet-hosted-services`.
### 6. Transversais
Configuração/Options (`aspnet-configuration-options`), logging estruturado sem dados sensíveis (`aspnet-logging`), métricas/traces se for caminho crítico (`dotnet-observability`), health check se nova dependência (`aspnet-health-checks`).
### 7. Testes (escreva junto, não depois)
- **Unitários** da regra (`dotnet-unit-testing` + `dotnet-xunit` ou `dotnet-mstest`).
- **Integração** do endpoint com `WebApplicationFactory` (`dotnet-integration-testing`), incluindo 400/401/403/404 e o caminho feliz.
- **Banco:** `efcore-testing` (a doc de EF desaconselha InMemory como substituto do banco real; os tutoriais oficiais usam InMemory só como demonstração).
- Estrutura e execução: `dotnet-test-automation`.
### 8. Quality gates (CONVENÇÃO) — só declare "pronto" se passar
1. `dotnet build` **sem warnings novos** (analyzers ligados — `dotnet-project-tooling`); `dotnet format --verify-no-changes`.
2. `dotnet test` verde (unit + integração).
3. Migration revisada e aplicável; sem mudança de modelo pendente.
4. **`dotnet-security-review`** aplicado ao que foi criado (injection, autorização, segredos, upload, desserialização).
5. **`dotnet-review-all`** no diff (mapeia sinais → skills e consolida achados).
6. NuGet Audit sem NU1901–NU1904 novos.

## Entregável da skill
Responda com: (a) decisões tomadas e as que **assumiu** (liste), (b) arquivos criados/alterados, (c) como rodar/testar (`dotnet` comandos), (d) resultado dos gates (o que passou/falhou/não foi executado), (e) pendências. **Não diga "feito" sem ter rodado build e testes**; se não puder executar, diga que não verificou.

## Checklist de revisão da execução do fluxo
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Entidade EF exposta/bindada diretamente na API | Alta |
| 2 | Endpoint sem autorização explícita ou sem checar dono do recurso | Alta |
| 3 | Mudança de modelo sem migration (ou migration não revisada) | Alta |
| 4 | Introduziu padrão/camada/biblioteca diferente do projeto sem pedir | Média |
| 5 | Service sem interface/DI correta; `DbContext` com lifetime errado; async bloqueante | Alta |
| 6 | Sem testes de integração do endpoint (401/403/404/validação) | Média |
| 7 | Validação só no cliente / DTO sem validação | Alta |
| 8 | Status codes/`Location`/`ProblemDetails` fora do padrão | Média |
| 9 | Declarou concluído sem rodar build/test | Alta |
| 10 | Feature cruza fronteira de módulo/camada | Média |

## Fontes oficiais (base do que é oficial nesta skill)
- APIs overview (Minimal APIs × controllers): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/apis
- Tutorial Minimal API: https://learn.microsoft.com/en-us/aspnet/core/tutorials/min-web-api
- Tutorial API com controllers: https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api
- Minimal APIs (referência): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis
- Integration tests: https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests
- Cada fase tem suas fontes na skill citada.
