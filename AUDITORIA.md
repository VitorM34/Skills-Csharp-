# Auditoria das skills contra a documentação oficial

Data: 2026-11-02. Escopo: as 83 skills com conteúdo (todas menos `dotnet-review-all`, que só mapeia sinais → skills).

## Método
Corpus local das docs oficiais (clones rasos): `dotnet/docs` (+ `samples`), `AspNetCore.Docs`, `EntityFramework.Docs`, NuGet, MSBuild, sql-docs (ADO.NET), azure-docs (Service Bus, App Configuration), GitHub Actions docs, OWASP WSTG/ASVS 5.0, rabbitmq-website + rabbitmq-dotnet-client, StackExchange.Redis + redis/docs, Serilog (wiki e sinks), Testcontainers, Docker Compose, Dapper, xUnit, Asp.Versioning, Mapperly/Mapster/AutoMapper, MongoDB (docs-csharp, docs-entity-framework), FluentValidation, MediatR (+ wiki), Hangfire, Quartz.NET, FeatureManagement.

Verificações (automáticas + conferência manual das exceções):
1. **URLs** (557 citadas): todas respondem 200 (exceto placeholders como `https://localhost`). Redirecionamentos de páginas movidas foram atualizados para o endereço atual.
2. **Identificadores** em código/`backticks` (APIs, tipos, propriedades): cada um foi procurado no corpus. Restaram apenas placeholders do próprio texto (`MeuHandler`, `<Nome>`…).
3. **Números e padrões** (defaults, limites, versões): 618 linhas candidatas (419 com números verificáveis) conferidas contra o corpus; as sem correspondência literal foram lidas uma a uma (eram formatação `1_000` vs `1.000`, números de linha de checklist ou versões de NuGet).
4. **IDs de regras** (CA/IDE/SYSLIB/ASPDEPR/SER…, 96 distintos): todos existem; os títulos das CA citadas foram comparados com o texto da skill.
5. **ASVS** (referências a requisitos 5.0): cada ID conferido com o texto do requisito.
6. **Afirmações normativas sem rótulo** (183 linhas com "sempre/nunca/evite/prefira"): amostra de ~40 conferida com a fonte; todas coerentes.

## Correções feitas nesta auditoria
- `efcore-saving-concurrency`: `AsyncFlowOption.Enabled` → `TransactionScopeAsyncFlowOption.Enabled` (nome correto).
- `dotnet-feature-flags`: filtros embutidos citados pelos nomes de tipo da doc (`PercentageFilter`, `TimeWindowFilter`, `ContextualTargetingFilter`, `TargetingFilter`); removidas inferências sem base (Percentage "aleatório", flag inexistente, `reloadOnChange`).
- `dotnet-mongodb`: removidos/ajustados `SortByDescending`, `CreateOneAsync`, "retry automático" de `WithTransaction`, aviso de log inventado e exemplos de injeção sem fonte.
- `dotnet-background-jobs`, `dotnet-mediatr-fluentvalidation`: removidas frases não sustentadas (cron do Hangfire, misfire do Hangfire, ordem de behaviors, painel do Quartz); links cruzados corrigidos.
- URLs de páginas movidas atualizadas em `aspnet-logging`, `dotnet-observability`, `csharp-nullable-references`, `dotnet-model-review`, `dotnet-dto-review`, `dotnet-security-review`, `dotnet-object-mapping`.

## O que esta auditoria NÃO prova
- Ela confirma que nomes, números, IDs e URLs existem e batem com a doc, e que as afirmações amostradas são fiéis. **Não** garante que cada frase parafraseada em português reproduz a doc sem nuance: isso só se verifica lendo skill e fonte lado a lado.
- Itens marcados "não li" nas skills continuam sem leitura (ex.: manual do servidor MongoDB, termos da licença comercial do MediatR, Hangfire Pro).
- Conteúdo marcado **CONVENÇÃO** é recomendação desta biblioteca, não da doc oficial.
- As skills não foram executadas contra projetos reais.
