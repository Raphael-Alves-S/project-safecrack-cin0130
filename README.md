1) Visão geral e requisitos implementados
------------------------------------------
Requisitos funcionais:
- Senha programável: existe um estado de programação (PROG) que coleta CODE_LEN entradas e grava como senha corrente.
- Tentativas limitadas: após 3 tentativas incorretas, entra em LOCKOUT por LOCK_S segundos.
- Feedback por LEDs: mapeamentos LEDG/LEDR indicam estados e progresso.
- Fluxo típico: PROG -> READY -> UNLOCK/ERROR_P -> LOCKOUT.

Requisitos não funcionais:
- FSM implementada em SystemVerilog.
- Simulação configurada (Waveform.vwf).

2) Lógica da programação
----------------------
- Parâmetros: CLOCK_HZ, LOCK_S, CODE_LEN.
- Entradas: clk, rst_sw, botões KEY[3:0], chaves SW.
- Saídas: LEDG, LEDR.
- Registradores para senha e tentativa.
- Contador de tentativas e LOCKOUT.


4) Mapa de pinos
----------------
- Clock: 50 MHz da DE2-115.
- Reset: chave (SW).
- Modo PROG: SW0.
- Botões: KEY[3:0].
- LEDs: LEDG[7] (PROG), LEDR[0] (erro), LEDR[1,2 e 3] (tentativas), LEDG[6](UNLOCK)
   LEDR[8](LOCKOUT)


5) Caso de uso
---------------------
1. Programação da senha.
2. Tentativa correta.
3. Tentativa errada e bloqueio.

6) Bugs conhecidos
-------------------
1. LEDs de erros de tentativas não acumulam, LEDR[1,2 e 3].
2. Reset inconsistente.
3. Comparação simples de senha.
4. Overflow de contador de LOCKOUT.
5. Pisca de erro irregular LEDR[0].
