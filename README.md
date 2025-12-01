# Task Mannager Offline First

**Laboratório de Desenvolvimento de Aplicações Móveis e Distribuídas**  
**Instituto de Ciências Exatas e Informática (ICEI) - PUC Minas**

---

## Implementação Mobile Offline-First

Aplicativo evoluído para operação completa sem internet, garantindo que dados criados ou editados offline sejam sincronizados automaticamente quando a conexão retornar.

### Requisitos Técnicos

1. **Persistência Local (SQLite):** Todas as tarefas são salvas localmente via `database_service.dart` antes de qualquer tentativa de envio à API.
2. **Detector de Conectividade:** O app utiliza `connectivity_plus` para alternar visualmente entre "Modo Online" (verde) e "Modo Offline" (vermelho/laranja).
3. **Fila de Sincronização:** Toda ação de CREATE/UPDATE/DELETE feita offline gera um registro na tabela `sync_queue` do SQLite.
4. **Resolução de Conflitos (LWW):** Implementação da lógica _Last-Write-Wins_. Se o servidor tiver uma versão mais recente, ela prevalece. Se a local for mais recente, ela é enviada ao servidor.

### Demonstração

1. **Prova de Vida Offline:** Coloque o dispositivo em "Modo Avião". Crie 2 tarefas e edite 1 existente. Os itens aparecem na lista local com ícone de "pendente/nuvem cortada".
2. **Persistência:** Feche o app completamente e abra novamente (ainda offline). Os dados permanecem salvos localmente.
3. **Sincronização:** Retorne à conexão. O app detecta a rede, envia os dados automaticamente e muda o ícone para "check/sincronizado".
4. **Prova de Conflito:** Simule uma edição no servidor (Postman) e uma no app simultaneamente, mostrando qual versão prevaleceu (LWW).
