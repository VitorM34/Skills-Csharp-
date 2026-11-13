---
name: dotnet-security-testing
description: Testar a segurança da sua própria aplicação .NET/ASP.NET Core (visão "hacker ético" defensiva) - plano de testes pelo OWASP WSTG e ASVS 5.0 (níveis L1/L2), modelagem de ameaças (Microsoft SDL), testes automatizados de segurança com WebApplicationFactory (autorização/IDOR-BOLA, mass assignment, JWT, CORS, headers, erros, lockout, rate limit, upload, SSRF), scanner ZAP (baseline passivo, API scan, full scan ativo só em ambiente próprio), regras de teste da Microsoft/Azure, severidade, relatório e reteste. Use quando o usuário quiser "testar a segurança do meu app", validar mitigações, fazer pentest interno, preparar checklist ASVS ou automatizar testes de segurança no CI. Fontes externas (OWASP, NIST, ZAP) marcadas; correções vêm das skills de segurança.
---

# Testes de segurança da sua aplicação (WSTG + ASVS)

**Proveniência:** a *metodologia* vem de fontes **externas** (OWASP WSTG, OWASP ASVS 5.0, NIST SP 800-115, documentação do ZAP) — marcadas **[EXT]**; o que a **Microsoft** diz está marcado **[MS]**; *como corrigir em .NET* vem das skills de segurança já escritas (base na doc oficial). Onde nenhuma fonte lida cobre algo, está dito.
**Uso:** testar a **sua** aplicação (código, ambiente de dev/staging, infraestrutura que é sua). Se o alvo for de outra pessoa/empresa, confirme com o dono — para o que é seu, não há nada a pedir. Esta skill **não** traz exploits prontos, ataques a terceiros, DoS nem evasão de detecção: o objetivo é **achar e corrigir** falhas no que você mantém.
Correção e revisão de código: `dotnet-security-review`, `aspnet-web-security`, `aspnet-authentication-authorization`, `aspnet-identity-data-protection`, `aspnet-validation`, `aspnet-rate-limiting`, `aspnet-error-handling`, `dotnet-json-serialization`. Testes: `dotnet-integration-testing`, `dotnet-xunit`, `dotnet-ci-cd`, `aspnet-openapi`.

## Antes de começar (30 segundos)
1. **Ambiente:** teste em **dev/staging com dados fictícios**; produção só com técnicas **passivas** (ver ZAP baseline). Tenha backup/rollback antes de scans ativos.
2. **Escopo:** liste URLs/serviços/ambientes que entram e o que fica fora; anote horários e quem avisar.
3. **Se hospeda no Azure [MS]:** as regras de teste da Microsoft **incentivam** testar **os seus próprios ativos** (fuzzing, port scan e vulnerability assessment nas suas VMs; gerar tráfego para testar capacidade; testar seu monitoramento/detecção; contas de teste/tenant de teste) e **proíbem**: DoS/DDoS, fuzzing de rede intensivo que gere tráfego excessivo, acessar dados/credenciais/tenants/contas de storage que não são seus e ações pós-exploração (movimento lateral, dump de segredos). Se achar uma vulnerabilidade **em serviço da Microsoft**, reporte ao MSRC (divulgação coordenada); se acessar dados indevidos por acidente, pare, avise e apague.

## O framework [EXT: WSTG]
O WSTG não é checklist rígido nem sequência fixa; são **6 atividades recorrentes**: (1) requisitos e política (use o **ASVS**), (2) **design/arquitetura e threat modeling**, (3) revisão de **código**, (4) **testes dinâmicos/pentest**, (5) **testes no pipeline de CI**, (6) testes contínuos/crowd. Princípios: **não existe bala de prata** (ferramenta não entende lógica de negócio/autorização), **priorize por risco** (uma quebra de autorização vale mais que dezenas de XSS de baixo risco), **teste continuamente**, **relate de forma acionável** (o que, como, causa raiz, correção, severidade, impacto).

## Passo 1 — Requisitos: escolha o nível do ASVS [EXT]
ASVS 5.0 = requisitos **verificáveis (pass/fail)** em 17 capítulos (V1 Encoding … V8 Authorization … V16 Logging e Error Handling). **L1** = mais crítico (comece aqui: 70 requisitos), L2 e L3 aumentam a profundidade. Para cada requisito: *documentação* (a decisão está escrita?) e *implementação* (o código faz isso?) são verificações separadas. Matriz L1 mapeada para .NET (IDs lidos no ASVS 5.0):
| ASVS L1 | O que verificar | Onde corrigir |
|---|---|---|
| **1.2.1–1.2.3** | encoding de saída por contexto (HTML, URL, JS) | `dotnet-security-review` (XSS), Razor encodes por padrão |
| **1.2.4** | consultas parametrizadas/ORM | `efcore-sql-performance` (FromSql vs FromSqlRaw) |
| **1.2.5 / 1.5.1** | sem command injection; XML sem entidades externas | `dotnet-security-review` (CA3006, CA3075) |
| **2.2.1 / 2.2.2** | validação positiva **no servidor** (cliente não conta) | `aspnet-validation` |
| **2.3.1** | fluxos de negócio na ordem esperada | testes de lógica (abaixo) |
| **3.3.1** | cookies `Secure` com prefixo `__Host-`/`__Secure-` | `aspnet-identity-data-protection` |
| **3.4.1** | HSTS em todas as respostas com **max-age ≥ 1 ano** | `aspnet-web-security` (⚠ ver nota HSTS) |
| **3.4.2 / 3.5.x** | CORS com valor fixo ou allowlist; métodos corretos (POST/PUT/PATCH/DELETE para ações sensíveis) | `aspnet-web-security` |
| **4.1.1** | `Content-Type` correto em toda resposta com corpo | `aspnet-http-endpoints` |
| **5.2.x / 5.3.x** | limite de tamanho, extensão esperada, arquivo enviado não executável, caminho gerado pelo app | `dotnet-security-review` (upload) |
| **6.2.1 / 6.2.5 / 6.2.4** | senha ≥ 8 (recomendado 15), **sem regras de composição**, checar contra as 3000 mais comuns | `aspnet-identity-data-protection` (⚠ ver nota senha) |
| **6.3.1 / 6.3.2** | anti brute force/credential stuffing; sem contas padrão (`admin`, `sa`) | `aspnet-rate-limiting`, Identity lockout |
| **7.2.x / 7.4.x** | token novo no login, sessão invalidada no logout/desativação de conta | Identity/JWT |
| **8.2.1 / 8.2.2 / 8.3.1** | autorização por **função** e por **dado (IDOR/BOLA)** aplicada em camada de **servidor confiável** | `aspnet-authentication-authorization` |
| **9.1.x / 9.2.1** | JWT validado (assinatura, **allowlist de algoritmos**, chaves de fonte confiável, expiração) | `aspnet-authentication-authorization`, CA5404 |
| **10.4.x** | OAuth/OIDC: redirect URI com allowlist exata, code de uso único e curto | `aspnet-authentication-authorization` |
| **11.3.x / 11.4.1** | sem ECB/padding fraco; só cifras (AES-GCM) e hashes aprovados | `dotnet-security-review` (cripto) |
| **12.1.1 / 12.2.x** | só TLS 1.2/1.3; TLS em toda conexão externa; certificado público confiável | `aspnet-hosting-deployment` |
| **13.4.1** | sem `.git`/`.svn` acessível no deploy | `aspnet-hosting-deployment` |
| **14.2.1 / 14.3.1** | segredos/tokens **nunca na URL/query**; limpar dados do cliente ao sair | `aspnet-web-security` |
| **15.1.1 / 15.2.1** | prazos de correção para dependências vulneráveis e cumprimento | NuGet Audit (`dotnet-ci-cd`) |
| **15.3.1** | retornar só o **subconjunto de campos** necessário (DTO) | `dotnet-dto-review` |
| **V16 (L2)** | logs de autenticação/autorização, sem dados sensíveis, mensagem genérica de erro, handler "de última instância", falhar de forma segura | `aspnet-logging`, `aspnet-error-handling` |
**Divergências com os defaults do ASP.NET que você deve decidir conscientemente:**
- **Senha:** o Identity vem exigindo maiúscula/minúscula/dígito/símbolo e **mínimo 6**; o ASVS L1 (6.2.5) **proíbe regras de composição** e pede ≥ 8 (15 recomendado). Ajuste `PasswordOptions` e verifique se há checagem contra senhas comuns (6.2.4) — a doc lida do Identity não menciona esse recurso.
- **HSTS:** o `UseHsts` usa 30 dias por padrão e a doc da Microsoft manda **começar com horas (no máximo 1 dia)** na 1ª implantação de HTTPS; o ASVS 3.4.1 exige **≥ 1 ano**. Combine: comece pequeno, **suba até ≥ 1 ano** quando estável.

## Passo 2 — Threat modeling (design) [MS]
A **Microsoft Threat Modeling Tool** é elemento do **SDL**: ajuda arquitetos a achar e mitigar problemas cedo (mais barato), comunicar o design de segurança, analisar com metodologia comprovada (a ferramenta oferece análise guiada **STRIDE per Element**) e gerenciar mitigações; é centrada em **software** (desenhe o diagrama da arquitetura e as fronteiras de confiança). Faça antes de features que mexem em autenticação, dados sensíveis ou integrações. (A lista de ameaças específicas do STRIDE não foi lida nesta pesquisa.)

## Passo 3 — Revisão de código e automação estática
`dotnet-security-review` (OWASP Top 10:2025 → docs oficiais) + **analyzers de segurança** ligados (`AnalysisModeSecurity`) + NuGet Audit. Isso cobre o que a análise estática enxerga; **não** substitui o teste dinâmico.

## Passo 4 — Testes dinâmicos por classe de falha [EXT: WSTG]
Categorias do WSTG (4.x) e o que verificar numa API/app .NET — **o comportamento seguro esperado**:
| WSTG | Verifique que… |
|---|---|
| 01 Information Gathering | headers/`Server`, `/swagger`, `/openapi`, `.well-known`, páginas de erro e metafiles **não vazam** versão, rotas internas ou stack trace em prod |
| 02 Config & Deployment | HSTS/CSP/headers de segurança presentes; métodos HTTP desnecessários desabilitados; sem arquivos de backup/`.git`; painéis admin não públicos |
| 03/04 Identity & Authentication | sem enumeração de contas (mesma resposta p/ usuário inexistente), **lockout** efetivo, sem credenciais padrão, reset de senha seguro, **MFA** onde exigido, credenciais só por canal cifrado |
| 05 Authorization | **IDOR/BOLA**: usuário A **não** acessa recurso do usuário B por ID; escalada de privilégio vertical bloqueada; *path traversal* bloqueado |
| 06 Session | cookies `Secure/HttpOnly/SameSite`; token novo no login; logout invalida; **JWT**: assinatura, algoritmo esperado, `exp/nbf/iss/aud` validados, sem dado sensível no payload; **CSRF** coberto se há cookie |
| 07 Injection | SQL/ORM/NoSQL/LDAP/XPath/comando/XML (XXE)/**SSRF**/Host header/template; **Mass Assignment**; **desserialização insegura**; HTTP verb tampering |
| 08 Error Handling | respostas genéricas; sem stack trace/consulta/segredo |
| 09 Weak Cryptography | só TLS moderno; sem dados sensíveis em canal não cifrado; primitivas fortes |
| 10 Business Logic | validação de regras, limites de uso, não pular etapas, upload de tipos inesperados/maliciosos |
| 11 Client-side | CORS correto, clickjacking (`frame-ancestors`/X-Frame-Options), redirects no cliente, WebSockets seguros |
| 12 API Testing | **BOLA**, **excessive data exposure** (retornar objeto inteiro), **BFLA** (função administrativa acessível a usuário comum), GraphQL se houver |
Observações do WSTG úteis em .NET: **Mass Assignment** ocorre quando o autobinding preenche campos que o usuário não deveria controlar (`role`, `isAdmin`, `status`, `balance`, `createdAt`) — remediação: **allowlist de campos/DTO** (`dotnet-dto-review`); **SSRF** é "dos mais difíceis de derrotar sem **allow lists** de IPs/URLs"; **JWT**: não confie em `jku/x5u/jwk` não verificados e valide sempre `exp`, `nbf`, `iss`, `aud`.

## Passo 5 — Transforme em testes automáticos (regressão de segurança)
Escreva os casos acima como **testes de integração** (`WebApplicationFactory`, `dotnet-integration-testing`) para rodar a cada build. Exemplos de intenção (adapte aos seus endpoints/usuários de teste):
```csharp
[Fact] // BOLA/IDOR: usuário B não lê pedido do usuário A
public async Task Order_of_another_user_returns_403_or_404()
{
    var orderId = await CreateOrderAs(clientUserA);
    var response = await clientUserB.GetAsync($"/orders/{orderId}");
    Assert.True(response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);
}

[Fact] // Mass assignment: campo privilegiado enviado no corpo é ignorado
public async Task Extra_privileged_field_is_ignored()
{
    var r = await clientUserA.PostAsJsonAsync("/profile", new { name = "Ana", isAdmin = true });
    var me = await clientUserA.GetFromJsonAsync<ProfileDto>("/profile");
    Assert.False(me!.IsAdmin);
}

[Theory] // Sem autenticação: endpoints protegidos retornam 401
[InlineData("/orders")] [InlineData("/admin/users")]
public async Task Protected_endpoint_requires_auth(string url)
    => Assert.Equal(HttpStatusCode.Unauthorized, (await anonymousClient.GetAsync(url)).StatusCode);
```
Outros bons candidatos: JWT expirado/`iss`/`aud` errados → 401; erro interno não retorna stack trace; resposta não contém campos extras; limite de tamanho/extensão no upload; `429` após N tentativas (`aspnet-rate-limiting`); headers de segurança presentes; CORS só para origens permitidas; lockout após N falhas.

## Passo 6 — Scanner dinâmico (DAST) [EXT: ZAP]
- **ZAP baseline** (`zap-baseline.py -t <url>`): roda o spider (padrão 1 min) e **apenas scan passivo** — "não realiza ataques"; poucos minutos; **ideal para CI/CD, inclusive contra produção**; por padrão tudo vira *WARN*; arquivo de config (`-c`) muda regras para FAIL/IGNORE; relatórios HTML/MD/XML/JSON; `-g` gera o config padrão; `-I` não falha em warning.
- **ZAP API scan** (`zap-api-scan.py -t <openapi.json> -f openapi`): importa **OpenAPI/SOAP/GraphQL** e faz scan **ativo** ajustado a APIs (não procura XSS); alerta respostas **5xx** e tipos de conteúdo atípicos. Use o OpenAPI gerado pela sua API (`aspnet-openapi`) — apenas em **ambiente seu de teste**.
- **ZAP full scan**: spider + **active scan = ataques reais**, pode rodar muito tempo ⇒ **somente staging próprio**, nunca produção, com dados fictícios e backup.
- Scanner acha "o conhecido"; **autorização, lógica de negócio e IDOR exigem os testes dirigidos do Passo 5** (princípio do WSTG).

## Passo 7 — Severidade, relatório e reteste
- **Priorize por risco** (impacto nos dados/negócio × facilidade), não por contagem [WSTG]. Critério de severidade/CVSS **não foi lido** nesta pesquisa: defina um modelo simples e documente (Crítica/Alta/Média/Baixa).
- **Relatório [EXT: WSTG Reporting / NIST SP 800-115]:** versão/data, **escopo**, **limitações** (áreas fora, funcionalidade quebrada, falta de acesso/tempo), **resumo executivo** (impacto no negócio, sem jargão), e por achado: **o que foi testado e como (reprodutível), causa raiz, impacto, severidade, correção recomendada (link para a skill/doc), evidência**; proteja/criptografe o relatório. O NIST SP 800-115 cobre planejar e conduzir testes, analisar achados e **desenvolver estratégias de mitigação**.
- **Reteste:** cada correção ganha um teste automático (Passo 5) que falha antes e passa depois.

## Checklist de revisão do programa de testes
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Sem teste dirigido de **IDOR/BOLA** e de **autorização por função** (scanner não pega) | Alta |
| 2 | Só scan automático; sem testes de lógica de negócio/mass assignment/JWT | Alta |
| 3 | Scan **ativo** (full/API scan) rodando em produção ou com dados reais | Alta |
| 4 | Nível ASVS-alvo não definido; requisitos sem documentação das decisões | Média |
| 5 | Defaults conflitantes ignorados (senha com composição/6 chars, HSTS curto para sempre) | Média |
| 6 | Achados sem causa raiz/severidade/correção; sem reteste automatizado | Média |
| 7 | Sem threat modeling antes de features sensíveis | Média |
| 8 | Testes de segurança fora do CI (rodados só "de vez em quando") | Média |
| 9 | Teste de DoS/carga destrutiva fora do seu ambiente (proibido pelas regras da Microsoft quando contra ativos dela) | Alta |
| 10 | Relatório/segredos coletados sem proteção | Média |

## Fontes
**[EXT] OWASP Web Security Testing Guide (WSTG):** https://owasp.org/www-project-web-security-testing-guide/
**[EXT] OWASP ASVS 5.0:** https://owasp.org/www-project-application-security-verification-standard/ · requisitos: https://github.com/OWASP/ASVS
**[EXT] NIST SP 800-115:** https://csrc.nist.gov/pubs/sp/800/115/final
**[EXT] ZAP — baseline / full / API scan:** https://www.zaproxy.org/docs/docker/baseline-scan/ · https://www.zaproxy.org/docs/docker/full-scan/ · https://www.zaproxy.org/docs/docker/api-scan/
**[MS] Regras de teste de segurança da Microsoft (MSRC):** https://www.microsoft.com/en-us/msrc/pentest-rules-of-engagement
**[MS] Microsoft Threat Modeling Tool:** https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool
**[MS] Correções em .NET:** ver as fontes de `dotnet-security-review`.
