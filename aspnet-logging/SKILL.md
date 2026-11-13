---
name: aspnet-logging
description: Implementar e revisar logging no .NET/ASP.NET Core - ILogger<T>, níveis de log, message templates com placeholders nomeados (structured logging), logar exceções, categorias, filtros em appsettings, provedores, scopes, EventId, desempenho. Use quando o usuário pedir para adicionar logs, configurar níveis, revisar logs com interpolação de string ou vazamento de dados sensíveis. Based on official Microsoft Learn docs.
---

# Logging no .NET / ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Para tratamento de erros: `aspnet-error-handling`, `dotnet-exception-handling`.

## Obter e usar o logger
`ILogger<TCategoria>` por DI (a categoria = nome completo do tipo). `ILoggerFactory` cria loggers com categoria arbitrária. Implementações em `Microsoft.Extensions.Logging`.
```csharp
public class OrdersService(ILogger<OrdersService> logger)
{
    public async Task<Order?> GetAsync(int id)
    {
        logger.LogInformation("Getting order {OrderId}", id);
        // ...
        logger.LogWarning("Order {OrderId} not found", id);
    }
}
```

## Message template (logging estruturado)
- Use **placeholders nomeados** (`{OrderId}`), **não números nem interpolação de string** (`$"..."`): os **valores são passados ao provedor** como campos (consultáveis), não só o texto formatado.
- **A ordem dos argumentos, não o nome do placeholder, determina o valor.** (`"{Pears}, {Bananas}, {Apples}", apples, pears, bananas` imprime `1, 2, 3`.)
- Exceções: use o overload com `Exception` (`logger.LogWarning(ex, "Falha em {Id}", id)`); o formato do registro da exceção depende do provedor.
- `EventId` (`LogEvent.GetItem = 1000`) identifica tipos de evento.

## Níveis (menor → maior)
| Nível | Valor | Uso (doc) |
|---|---|---|
| Trace | 0 | mais detalhado; pode conter **dados sensíveis**; desabilitado por padrão e **não habilitar em produção** |
| Debug | 1 | depuração/desenvolvimento; cuidado em produção (alto volume) |
| Information | 2 | fluxo geral |
| Warning | 3 | eventos anormais/inesperados que não derrubam a app |
| Error | 4 | falhas na operação atual |
| Critical | 5 | falhas que exigem atenção imediata (perda de dados, disco cheio) |
Habilitar um nível habilita ele e os mais severos. **Padrão sem configuração: `Information`.** Recomendação: `"Default": "Information"` e `"Microsoft.AspNetCore": "Warning"`; para investigar, suba Trace/Debug **só nas categorias investigadas**.

## Configurar
```json
{ "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" },
               "Debug": { "LogLevel": { "Default": "Information" } } } }
```
- `Logging:{Provider}:LogLevel` **sobrescreve** `Logging:LogLevel` para aquele provedor (aliases: Console, Debug, EventSource, EventLog, Azure...). Categoria específica vence a `Default`.
- **Regras de filtro:** seleciona regras do provedor (ou sem provedor), depois as de **prefixo de categoria mais longo**; sem match, as sem categoria.
- Defina o nível mínimo na **configuração**, não em C# (`SetMinimumLevel` existe; a doc recomenda a configuração). Há filtros em código e função de filtro.
- A API de logging **não muda nível em runtime**; providers de configuração com recarga (JSON) fazem efeito imediato.
- Provedores padrão do `CreateBuilder`: Console, Debug, EventSource (e EventLog no Windows). Para trocar: `builder.Logging.ClearProviders()` + adicionar os desejados. Provedores de terceiros (Serilog, NLog...) existem; a doc não os especifica.
- Logs durante a construção do host/startup: ver "Log during host construction". **Não há métodos assíncronos de logger** (logar é rápido; escreva em armazenamento lento de forma assíncrona fora do logger).
- Escopos de log com `SpanId`/`TraceId`/`ParentId` automáticos (ver "Automatically log scope with SpanId...").

## Boas práticas derivadas da doc
1. Template com placeholders nomeados; nunca concatenar/interpolar.
2. Logue exceções com o overload de exceção; não engula nem logue e relance sem necessidade (duplica).
3. Nunca logue segredos/dados pessoais; Trace pode conter dados sensíveis.
4. Níveis coerentes; volume alto em Debug/Trace só sob investigação.
5. Categoria pelo tipo (`ILogger<T>`).
6. Para caminhos quentes use o **source generator `LoggerMessage`** (doc "High-performance logging"; confirmar antes de detalhar a sintaxe).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `logger.LogX($"...{x}")` (interpolação) → template com placeholders |
| 2 | Placeholders numéricos/ordem trocada |
| 3 | `catch` sem logar a exceção (ou log sem o objeto `Exception`) |
| 4 | Dados sensíveis em mensagens/scopes |
| 5 | Nível errado (Information para erro; Error para fluxo normal) |
| 6 | Nível Trace/Debug habilitado globalmente em produção |
| 7 | `Console.WriteLine` no lugar de `ILogger` |
| 8 | Configuração de níveis por categoria em `appsettings` coerente com o ambiente |
| 9 | Loop quente com muitos logs sem source generator/filtragem |

## Fontes oficiais
- Logging in .NET and ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/logging/
- Logging in .NET (extensões): https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/overview
- High-performance logging (LoggerMessage): https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/high-performance-logging
