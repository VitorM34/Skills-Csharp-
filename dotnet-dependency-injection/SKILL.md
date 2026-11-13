---
name: dotnet-dependency-injection
description: Implementar e revisar injeção de dependência em .NET/ASP.NET Core (IServiceCollection, AddScoped/AddTransient/AddSingleton, tempos de vida, captive dependency, escopo, IDisposable, keyed services, service locator, BackgroundService com escopo, constructor injection). Use quando o usuário pedir para registrar services, verificar lifetimes, ou revisar DI. Based on official Microsoft Learn docs.
---

# Injeção de Dependência em .NET — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim); caso contrário, buscar antes.

## Conceito
DI = Inversão de Controle entre classes e dependências, embutida no .NET (junto com configuration, logging, options). Dependência concreta criada com `new` dentro da classe é problema: trocar implementação exige alterar a classe, configurar dependências ficam espalhadas, e dificulta teste (não dá para mockar).

Solução: (1) abstrair via interface/classe base, (2) registrar no container (`IServiceCollection` → `IServiceProvider`), (3) injetar pelo **construtor**. O framework cria e descarta as instâncias.

```csharp
builder.Services.AddSingleton<IMessageWriter, LoggingMessageWriter>();

public sealed class Worker(IMessageWriter messageWriter) : BackgroundService { /* ... */ }
```
`ILogger<T>` é resolvido por tipos genéricos abertos; não é preciso registrar cada `ILogger<X>`.

## Regras de construtor (doc)
- Precisa de construtor **public** para ser resolvido pelo container.
- Com vários construtores, vence o que tem **mais parâmetros resolvíveis**; se houver ambiguidade → exceção. Solução: um construtor que aceita os dois tipos.
- Parâmetros não providos pela DI precisam de valor default.
- `ActivatorUtilities` cria objetos não registrados; exige só um construtor aplicável.

## Projetar services para DI
- Evitar classes/membros **estáticos com estado**; usar singleton em vez de estado global.
- Evitar `new` de dependências dentro de services.
- Services pequenos, bem fatorados, testáveis. Muitas dependências injetadas = sinal de violar SRP: refatorar.

## Os três lifetimes (doc "Service lifetimes")
| Lifetime | Criação | Uso típico / regras |
|---|---|---|
| **Transient** (`AddTransient`) | cada vez que é solicitado ao container | leve e sem estado; descartado ao fim da requisição (aloca a cada resolução) |
| **Scoped** (`AddScoped`) | uma vez por requisição/cliente (ou por escopo explícito) | `AddDbContext` do EF Core já registra como scoped; **sempre usar dentro de um escopo**; descartado no fim da requisição |
| **Singleton** (`AddSingleton`) | primeira solicitação (ou instância entregue pelo desenvolvedor) | **precisa ser thread-safe**; frequentemente sem estado; vive até o shutdown (cuidado com memória) |
Resolver: ✔ singleton a partir de scoped/transient; ✔ scoped a partir de scoped/transient; ✖ **scoped dentro de singleton** por construtor ou `IServiceProvider` (vira singleton de fato) — aceitável só com escopo explícito via `IServiceScopeFactory`. Não implemente o padrão Singleton manualmente nem descarte singletons registrados: o container gerencia. Em Development, o container lança exceção ao resolver serviço de lifetime mais curto a partir de um mais longo (scope validation).

## Tempos de vida e descarte
- **Transient/Scoped**: descartados no fim do escopo em que foram resolvidos (em apps web, normalmente ao fim da requisição). **Singleton**: descartado quando o container é descartado (encerramento).
- O container chama `Dispose/DisposeAsync` nos tipos que **ele** cria. Nunca descarte você mesmo um service resolvido do container. Instância passada pronta (`AddSingleton(new X())`) **não** é descartada pelo framework.
- Não registre `IDisposable` como transient (use factory); não resolva transient/scoped descartáveis no escopo raiz (vazamento de memória).
- Receber `IDisposable` por DI não obriga o receptor a implementar `IDisposable`.
- Use singleton só para serviços com estado próprio caro ou globalmente compartilhado; sem estado → evite singleton. Singleton exige **thread safety**; o container é thread-safe ao resolver, mas isso não torna thread-safe as instâncias.

## Armadilhas (anti-patterns da doc)
1. **Captive dependency**: singleton que recebe scoped no construtor (ex.: `Foo(Bar)` com `Foo` singleton e `Bar` scoped) → o scoped vive como singleton. Detectar com **scope validation** (`validateScopes: true`; ligado por padrão em Development com `CreateApplicationBuilder`).
2. **Scoped resolvido fora de escopo** vira singleton na prática.
3. **Service locator** (`GetService` onde DI serve; injetar factory que resolve em runtime): evitar.
4. **`BuildServiceProvider` durante o registro**: evitar; use overloads que recebem `IServiceProvider`.
5. **Factory async com `.Result`** → deadlock. DI não suporta resolução async; chame métodos async depois de resolver.
6. **Guardar `IApplicationBuilder.ApplicationServices` em estático**; acesso estático a services.
7. **Colocar dados/configuração no container** (ex.: carrinho do usuário). Configuração → options pattern.
8. **BackgroundService/IHostedService (singleton) com dependências scoped**: injetar `IServiceScopeFactory`, criar escopo (`using var scope = factory.CreateScope()`), resolver dentro.

## Keyed services
`AddKeyedSingleton<IMessageWriter, QueueMessageWriter>("queue")` e consumo com `[FromKeyedServices("queue")]`. Chave pode ser qualquer `object` com `Equals` correto. Desde .NET 10, `GetKeyedService` (singular) com `KeyedService.AnyKey` lança `InvalidOperationException`.

## Container padrão vs terceiros
Use o embutido, a menos que precise de: property injection, child containers, lifetime customizado, `Func<T>` lazy, registro por convenção.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Dependência criada com `new` em vez de injetada |
| 2 | Registro interface→implementação com lifetime coerente |
| 3 | Singleton dependendo de scoped/transient (captive) |
| 4 | Service stateful registrado como singleton sem thread safety |
| 5 | Service stateless registrado como singleton desnecessariamente |
| 6 | `IDisposable` transient / dispose manual de service do container |
| 7 | Uso de `GetService`/service locator, `BuildServiceProvider` no registro |
| 8 | Construtor com muitas dependências (SRP) / construtores ambíguos |
| 9 | Hosted service consumindo scoped sem `IServiceScopeFactory` |
| 10 | Estado estático ou acesso estático a services |

## Fontes oficiais
- Visão geral: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/overview
- Guidelines: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines
- Service lifetimes: https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/service-lifetimes
- DI no ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection
