---
name: dotnet-modular-monolith
description: Projetar, implementar e revisar um monolito modular em .NET / ASP.NET Core - módulos como bounded contexts, encapsulamento, dependência por abstrações/contratos, banco por módulo, comunicação entre módulos, quando monolito vs microserviços. Use quando o usuário quiser criar uma aplicação do zero em monolito modular, verificar a separação em módulos ou preparar para extrair microserviços depois. Based on official Microsoft Learn architecture principles (note - Microsoft has no dedicated modular-monolith guide).
---

# Monolito modular em .NET — projetar e revisar

## ⚠️ Honestidade sobre as fontes
Na pesquisa feita, o Microsoft Learn **não tem um guia oficial de "monolito modular"**; só há um episódio em vídeo (*On .NET Live: Modular Monoliths with ASP.NET Core*). O que a documentação oficial **fornece** são os princípios que sustentam o padrão: *separation of concerns*, *encapsulation*, *dependency inversion*, *explicit dependencies*, *single responsibility*, *persistence ignorance*, *bounded contexts*, arquitetura em camadas / Clean Architecture e a advertência de que microserviços custam complexidade.
Esta skill separa **[OFICIAL]** (cada afirmação com base nas páginas citadas) de **[CONVENÇÃO]** (prática comum da comunidade, **não** documentada pela Microsoft: apresente como sugestão e diga isso ao usuário).

## [OFICIAL] Fundamentos
1. **Monolito** = aplicação autocontida, implantada como uma unidade; pode ter vários projetos/camadas (N-Layer) e ainda ser um único deploy. Camadas = separação lógica; tiers = separação física.
2. **Separation of concerns:** regras de negócio separadas de infraestrutura e UI; o núcleo de negócio idealmente num projeto que **não depende** dos outros.
3. **Encapsulation:** cada parte expõe contratos bem definidos; o interior pode mudar sem quebrar colaboradores. **Estado global mutável** (incluindo banco central compartilhado como integração) vai contra a encapsulação.
4. **Dependency inversion + DI:** dependências apontam para abstrações; implementações são ligadas no *composition root* (`Program.cs`).
5. **Explicit dependencies:** classes declaram no construtor o que precisam.
6. **Single responsibility** também em nível arquitetural; levado ao extremo vira microserviços.
7. **Persistence ignorance:** o modelo de negócio não deve exigir classe base, interface, construtor sem parâmetros, `virtual` ou atributos de persistência (ideal; EF Core exige algumas concessões, ver `dotnet-model-review`).
8. **Bounded contexts (DDD):** módulos conceituais separados, cada um com **seus próprios nomes e acesso exclusivo ao seu armazenamento**; a comunicação entre contextos é por **interfaces programáticas, não por banco compartilhado**. "Mapeiam de perto para microserviços".
9. **Monolito primeiro é legítimo:** microserviços só valem se há fatias de funcionalidade independentes, necessidade de escalar partes isoladas e fronteiras já claras; no início do MVP as fronteiras naturais podem não ter emergido. Separar em processos adiciona comunicação assíncrona, resiliência, consistência eventual. Escalar clonando a instância inteira costuma ser simples e barato.
10. Camadas permitem trocar implementações (ex.: persistência) e usar fakes em testes.

## [CONVENÇÃO] Como aplicar os princípios num monolito modular (sugestão, não oficial)
Apresente como proposta derivada dos princípios acima:

```
src/
  Host/                      # ASP.NET Core: Program.cs, composition root, middleware, ProblemDetails
  Modules/
    Orders/
      Orders.Contracts/      # DTOs/eventos/interfaces públicas do módulo (a única API visível)
      Orders.Core/           # entidades, regras (internal por padrão)
      Orders.Infrastructure/ # DbContext próprio, repositórios, migrations
      Orders.Api/            # endpoints do módulo (Minimal API MapGroup / controllers)
    Catalog/ ...
  Shared/                    # apenas abstrações mínimas e neutras
```
Regras sugeridas (cada uma decorre de um princípio oficial):
- Tipos `internal` por padrão; só `Contracts` é `public` (encapsulation).
- Um módulo **não referencia** o Core/Infrastructure de outro; só `Contracts` (dependency inversion / bounded contexts).
- **Um DbContext e esquema por módulo**; nada de joins entre módulos nem FK cruzada (acesso exclusivo ao armazenamento).
- Comunicação entre módulos por interface pública ou evento em processo; DTOs de contrato, nunca entidades.
- Cada módulo registra seus serviços num método de extensão `AddOrdersModule(this IServiceCollection)` chamado pelo Host (composition root).
- Endpoints do módulo via `MapGroup` (ver `aspnet-minimal-api`).
- Teste de arquitetura para impedir referências proibidas (ferramenta de terceiros; não coberta pela doc).
- Se algum dia extrair microserviço: o módulo já tem fronteira, contratos e dados próprios.

## Checklist de revisão
| # | Verificar | Base |
|---|---|---|
| 1 | Módulo A referencia tipos internos do módulo B | encapsulation / bounded context |
| 2 | Tabelas/DbContext compartilhados entre módulos, joins cruzados | bounded contexts (acesso exclusivo ao store) |
| 3 | Entidades vazando como contrato entre módulos ou na API | encapsulation, `dotnet-dto-review` |
| 4 | Núcleo de negócio dependendo de infraestrutura/EF/ASP.NET | separation of concerns / dependency inversion |
| 5 | `new` de colaboradores, service locator, estático com estado | explicit dependencies, DI guidelines |
| 6 | Módulo com mais de uma responsabilidade de negócio | SRP / bounded context |
| 7 | Registro de DI espalhado em vez de por módulo + composition root | composition root |
| 8 | Fronteiras prematuramente quebradas em microserviços sem necessidade | guia de arquiteturas |
| 9 | Estado global mutável (static) para integrar módulos | encapsulation |
| 10 | Convenções [CONVENÇÃO] apresentadas como se fossem oficiais | honestidade |

## Fontes oficiais
- Architectural principles: https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/architectural-principles
- Common web application architectures (monolito, camadas, Clean Architecture): https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures
- Microservices architecture style (quando/por que): https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/microservices
- DI guidelines: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines
- On .NET Live — Modular Monoliths with ASP.NET Core (vídeo): https://learn.microsoft.com/en-us/shows/on-dotnet/on-dotnet-live-modular-monoliths-with-aspnet-core
- Complementos não oficiais (comunidade; apenas referência): Milan Jovanović — https://milanjovanovic.tech/blog/build-modular-monolith-dotnet-step-by-step.md ; Chris Schneider — https://chrlschn.dev/blog/2024/01/a-practical-guide-to-modular-monoliths/
