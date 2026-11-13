---
name: aspnet-performance-best-practices
description: Revisar e aplicar boas práticas de desempenho e correção em apps ASP.NET Core - evitar bloqueio de threads, paginação, IAsyncEnumerable, alocações grandes (LOH), HttpClientFactory, tarefas longas fora do request, leitura assíncrona do corpo, HttpContext em threads de fundo, IHttpContextAccessor, headers após corpo iniciado. Use quando o usuário pedir otimização, revisão de performance ou investigar thread pool starvation/OOM. Based on official Microsoft Learn docs (ASP.NET Core Best Practices).
---

# ASP.NET Core — boas práticas de desempenho e uso correto de HttpContext

Só afirmar o que a doc oficial diz (fontes no fim). Medir antes de otimizar: a doc recomenda **medir o impacto** antes de adotar técnicas de alto desempenho (complexidade pode não compensar).

## Princípios
- **Cache agressivo** (ver `aspnet-caching`); **entenda os hot code paths** (código chamado por quase toda requisição ou em loops) e mantenha-os rápidos; **use a versão mais recente** do ASP.NET Core; **comprima respostas** e **minifique assets**.

## Evite chamadas bloqueantes (a regra nº 1)
- Projetado para muitas requisições simultâneas: APIs assíncronas deixam poucas threads atenderem milhares de requisições.
- ✖ `Task.Wait()`/`.Result`/`GetAwaiter().GetResult()` bloqueando código assíncrono. ✖ **Locks** em caminhos comuns. ✖ `Task.Run` seguido de `await` imediato: o ASP.NET já roda código em threads do pool; só adiciona agendamento; **não** use `Task.Run` para tornar uma API síncrona assíncrona.
- ✔ Controller/Razor Page actions **assíncronas** e call stack inteiro assíncrono. Ver `csharp-async-await`.
- **Bloqueio de thread → thread pool starvation** (latência, timeouts).

## Dados e I/O
- Não traga mais dados que o necessário (consulte só o preciso); **minimize round trips**; **no-tracking** em leitura (`efcore-querying`); evite projeções sobre coleções que geram **N+1**; queries compiladas só se medido.
- **Paginação** para coleções grandes (page size/index); retornar listas enormes bloqueia recursos.
- **`IEnumerable<T>` na action** → o serializador itera de forma **síncrona** (bloqueio, starvation): use `ToListAsync` antes de retornar ou `IAsyncEnumerable<T>` (com `System.Text.Json` há streaming; ver `aspnet-controllers`).

## Memória
- Minimize **alocações de objetos grandes** em hot paths (LOH é coletado só em GC completo/Gen2: mais caro). **Evite ler corpos grandes de request/response para a memória**: risco de OOM e **negação de serviço**.
- Serializadores só síncronos (ex.: Json.NET) exigem cuidado; `System.Text.Json` é o padrão desde o ASP.NET Core 3.0 e é assíncrono.

## Leitura de request/response
- Toda I/O é assíncrona: **não use leitura síncrona** do corpo (`ReadToEnd` = sync over async). Use `ReadFormAsync` em vez de `Request.Form` (que só é seguro em condições específicas).
- Não assuma que `HttpRequest.ContentLength` é não nulo.

## HttpContext e escopo
- ✖ **Não guarde `IHttpContextAccessor.HttpContext` em campo**; ✖ **não acesse `HttpContext` de várias threads** (não é thread-safe); ✖ **não use `HttpContext` depois do fim da requisição** (é reciclado; `async void` é **SEMPRE** má prática: a requisição "termina" no primeiro `await`); ✖ **não capture `HttpContext` nem serviços da requisição (ex.: `DbContext` scoped) em threads/tarefas de fundo** (`ObjectDisposedException`). ✔ Copie os dados necessários durante a requisição; em fundo use **`IServiceScopeFactory`** (singleton) para criar um escopo próprio; implemente tarefas longas como **hosted services** (`aspnet-hosted-services`).
- ✖ **Não modifique status/headers depois que o corpo começou**; ✖ não chame `next()` depois de começar a escrever o corpo (ver `aspnet-middleware-pipeline`).

## Outros
- **`HttpClientFactory`** (pool de conexões): não crie/descarte `HttpClient` por requisição (`dotnet-httpclient-resilience`).
- **Tarefas longas fora do request**: não espere tarefas longas dentro do processamento normal; use fila + hosted service.
- **Middleware**: não ponha tarefas longas em middleware customizado (afeta todas as requisições).
- **Exceções devem ser raras**: lançar/capturar é lento; não use para controle de fluxo, sobretudo em hot paths.
- **IIS:** hospedagem **in-process** (padrão desde o ASP.NET Core 3.0).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `.Result`/`.Wait()`/sync-over-async | Alta |
| 2 | `async void` fora de event handler; `HttpContext` usado após a requisição | Alta |
| 3 | `DbContext`/`HttpContext` capturado em tarefa de fundo | Alta |
| 4 | Corpo grande lido inteiro na memória (`ReadToEnd`, `ToArray`) | Alta |
| 5 | Lista sem paginação; `IEnumerable<T>` retornado sem materializar | Média |
| 6 | `Task.Run` em handler de requisição | Média |
| 7 | Lock em caminho comum | Média |
| 8 | `Request.Form` síncrono; `ContentLength` assumido | Média |
| 9 | Exceção usada como fluxo normal | Média |
| 10 | Headers/status alterados após o corpo; `next()` após escrever | Média |
| 11 | Falta compressão/cache onde faz sentido | Baixa |

## Fontes oficiais
- ASP.NET Core Best Practices: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices
- Performance overview: https://learn.microsoft.com/en-us/aspnet/core/performance/overview
- Memory management: https://learn.microsoft.com/en-us/aspnet/core/performance/memory
- Hosted services: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services
