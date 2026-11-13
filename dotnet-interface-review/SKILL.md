---
name: dotnet-interface-review
description: Implementar e revisar interfaces em C#/.NET (declarar interface, implementação implícita/explícita, herança de interfaces, default interface members, interface vs classe abstrata, ISP, nomenclatura IFoo, interface de service/repository). Use quando o usuário pedir para criar uma interface, verificar se a implementação da interface está correta, ou decidir entre interface e classe abstrata. Based on official Microsoft Learn docs.
---

# Interfaces em C#/.NET — implementar e revisar

Regra de ouro: só afirmar o que a doc oficial diz (fontes no fim); fora disso, buscar antes de responder.

## O que a doc diz

- Interface = **contrato**: métodos, propriedades, eventos, indexadores. Não pode ter campos de instância, construtores de instância nem finalizers. Membros são `public` por padrão (pode usar `internal` etc.).
- Convenção: nome começa com `I` (`ILogger`).
- Classe/struct lista interfaces após `:`; **deve implementar todos os membros** (exceto os que têm implementação default). Pode implementar várias; herda no máximo uma classe base.
- **Implementação explícita** (`double IMetric.GetDistance()`): usar quando duas interfaces têm o mesmo membro ou para manter a API pública limpa. Só acessível via variável do tipo da interface. Obrigatória quando a assinatura usa tipos `internal` e a classe é pública.
- **Herança de interface:** quem implementa `IShape : IDrawable` implementa os membros de ambas.
- **Interface vs classe abstrata:**
  - Classe abstrata → tipos relacionados que compartilham estado (campos), construtores, membros não públicos; permite adicionar membros com comportamento padrão sem quebrar derivados.
  - Interface → contrato que atravessa hierarquias não relacionadas ou múltiplos contratos; única opção comum para structs.
- Recursos avançados: *default interface members* e *static abstract members*.

## Framework Design Guidelines (Interface Design)

- ✔ Defina interface quando um conjunto de tipos (inclusive value types) precisa de API comum.
- ✔ Considere interface para dar a funcionalidade a tipos que já herdam de outro.
- ✖ **Evite marker interfaces** (sem membros): use atributo.
- ✔ Forneça ao menos **um tipo que implemente** a interface e ao menos **uma API que a consuma** (valida o design).
- ✖ **Não adicione membros a uma interface já publicada**: quebra implementadores; crie nova interface. (Default interface members existem, mas a regra de design continua valendo para libs publicadas; avalie a doc de versionamento antes de recomendar.)
- Fora essas situações, a diretriz geral para **bibliotecas reutilizáveis** é preferir classes. Em aplicações, interfaces para DI/testes são prática comum e coberta pela doc de DI (ver `dotnet-dependency-injection`).

## Como implementar (passo a passo)

1. Dê nome `IAlgo` com responsabilidade única; poucos membros coesos.
2. Declare só o que os **consumidores** precisam.
3. Implemente numa classe `public`/`internal` (conforme o escopo) com todos os membros; use `sealed` quando não for herdada.
4. Registre no container de DI: `services.AddScoped<IFoo, Foo>();`.
5. Consumidores recebem `IFoo` no construtor, nunca `new Foo()`.

```csharp
public interface IOrderService
{
    Task<OrderDto?> GetAsync(Guid id, CancellationToken ct = default);
    Task<OrderDto> CreateAsync(CreateOrderRequest request, CancellationToken ct = default);
}

public sealed class OrderService(IOrderRepository repository) : IOrderService
{
    public async Task<OrderDto?> GetAsync(Guid id, CancellationToken ct = default) { /* ... */ }
    public async Task<OrderDto> CreateAsync(CreateOrderRequest request, CancellationToken ct = default) { /* ... */ }
}
```
(Métodos assíncronos retornam `Task`/`Task<T>` e terminam em `Async`: ver `csharp-async-await`.)

## Checklist de revisão

| # | Verificar | Problema |
|---|---|---|
| 1 | Todos os membros implementados, assinaturas idênticas (tipo de retorno, parâmetros, nullability) | Não compila / contrato violado |
| 2 | Nome começa com `I`; sem sufixo de implementação | Convenção |
| 3 | Interface com muitos membros não coesos | Contrato inchado; dividir |
| 4 | Interface sem nenhuma implementação ou consumidor | Design não validado (guideline) |
| 5 | Marker interface (vazia) | Preferir atributo |
| 6 | Interface publicada recebeu novo membro | Quebra implementadores; criar nova interface |
| 7 | Conflito de nomes entre interfaces resolvido de forma implícita | Usar implementação explícita |
| 8 | Classe usa `new Concreta()` em vez de receber a interface | Acoplamento; usar DI |
| 9 | Implementação de método `void` da interface como `async void` | Não aguardável; interface deveria retornar `Task` |
| 10 | Membro explícito necessário mas implementado `public` com tipos `internal` | Erro de acessibilidade |
| 11 | Interface onde classe abstrata é mais adequada (estado compartilhado/ctor) | Reavaliar escolha |

## Formato da resposta
Para cada interface/implementação: veredito (correta / com ajustes), lista de achados (severidade, trecho, motivo + fonte, correção). Se estiver correta, diga o que verificou.

## Fontes oficiais
- Interfaces (C#): https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/interfaces
- Referência da palavra-chave `interface`: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/interface
- Explicit interface implementation: https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/interfaces/explicit-interface-implementation
- Framework Design Guidelines — Interface Design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/interface
