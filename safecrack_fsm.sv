
module safecrack_fsm #(
    parameter int CLOCK_HZ = 50_000_000,
    parameter int LOCK_S   = 10,
    parameter int CODE_LEN = 4
)(
    input  logic        clk,
    input  logic        rst_sw,   // 1: modo programação (mantém PROG); borda ↑ faz reset/limpeza
    input  logic        KEY0_n,
    input  logic        KEY1_n,
    input  logic        KEY2_n,
    input  logic        KEY3_n,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG
);

    // --- Entradas de botões (ativos em alto) ---
    logic key0, key1, key2, key3;
    assign key0 = ~KEY0_n;
    assign key1 = ~KEY1_n;
    assign key2 = ~KEY2_n;
    assign key3 = ~KEY3_n;


    // --- Sincronização e borda de subida do rst_sw ---
    logic rst_d, rst_q;
    always_ff @(posedge clk) begin
        rst_d <= rst_sw;
        rst_q <= rst_d;
    end
    wire rst_rise = rst_d & ~rst_q;  // pulso de 1 ciclo quando rst_sw sobe
    wire rst_on   = rst_d;           // rst_sw sincronizado (nível)

    // --- Estados ---
    typedef enum logic [2:0] {
        PROG, READY, ENTRY, VERIFY, UNLOCK, ERROR_P, LOCKOUT
    } state_t;

    state_t state, next;


    // --- Detecção de borda de botões ---
    logic [3:0] keys_async, keys_sync_d, keys_sync_q;
    assign keys_async = {key3, key2, key1, key0};

    always_ff @(posedge clk) begin
        keys_sync_d <= keys_async;
        keys_sync_q <= keys_sync_d;
    end

    logic [3:0] keys_posedge;
    assign keys_posedge       = keys_sync_d & ~keys_sync_q;
    wire        key_pressed_pulse = |keys_posedge;

    logic [1:0] key_value;
    always_comb begin
        key_value = 2'bxx;
        if      (keys_posedge[0]) key_value = 2'b00;
        else if (keys_posedge[1]) key_value = 2'b01;
        else if (keys_posedge[2]) key_value = 2'b10;
        else if (keys_posedge[3]) key_value = 2'b11;
    end

    // --- Registradores principais ---
    logic [CODE_LEN*2-1:0] pass_code, attempt_code;
    logic [$clog2(CODE_LEN+1)-1:0] idx;
    logic [1:0] tries;

    // --- Temporizadores ---
    localparam int ERR_PULSE_CYCLES = CLOCK_HZ / 5;
    localparam int LOCK_CYCLES      = CLOCK_HZ * LOCK_S;

    logic [$clog2(ERR_PULSE_CYCLES + 1) - 1:0] err_cnt;
    logic [$clog2(LOCK_CYCLES + 1)      - 1:0] lock_cnt;

    // --- Função push_digit ---
    function automatic logic [CODE_LEN*2-1:0] push_digit
    (
        input logic [CODE_LEN*2-1:0] curr,
        input logic [1:0]            dig
    );
        push_digit = {curr[CODE_LEN*2-3:0], dig};
    endfunction

    // ==============================================================
    //  SEQUENCIAL: reset one-shot + operação
    // ==============================================================
    always_ff @(posedge clk) begin
        // Reset/limpeza somente na borda de subida do rst_sw
        if (rst_rise) begin
            state        <= PROG;
            idx          <= '0;
            pass_code    <= '0;
            attempt_code <= '0;
            tries        <= '0;
            err_cnt      <= '0;
            lock_cnt     <= '0;
        end else begin
            // Próximo estado
            state <= next;

            // Captura de senha durante PROG (rst_sw pode permanecer 1 sem zerar tudo)
            if (state == PROG) begin
                if (key_pressed_pulse && (idx < CODE_LEN)) begin
                    pass_code <= push_digit(pass_code, key_value);
                    idx       <= idx + 1'b1;
                end
            end

            // Captura da tentativa
            if (state == ENTRY) begin
                if (key_pressed_pulse && (idx < CODE_LEN)) begin
                    attempt_code <= push_digit(attempt_code, key_value);
                    idx          <= idx + 1'b1;
                end
            end

            // Verificação e tentativas
            if (state == VERIFY) begin
                if (attempt_code == pass_code) begin
                    tries <= '0;
                end else if (tries != 2'd3) begin
                    tries <= tries + 1'b1;
                end
            end

            // Contadores
            if (state == ERROR_P) begin
                if (err_cnt < ERR_PULSE_CYCLES[$clog2(ERR_PULSE_CYCLES+1)-1:0])
                    err_cnt <= err_cnt + 1'b1;
            end else if (state == LOCKOUT) begin
                if (lock_cnt < LOCK_CYCLES[$clog2(LOCK_CYCLES+1)-1:0])
                    lock_cnt <= lock_cnt + 1'b1;
            end else begin
                err_cnt  <= '0;
                lock_cnt <= '0;
            end

            // Reset de índice/entrada ao entrar em ENTRY
            if ((next == ENTRY) && (state != ENTRY)) begin
                idx          <= '0;
                attempt_code <= '0;
            end

            // Limpa tentativas ao sair do LOCKOUT
            if ((next == READY) && (state == LOCKOUT)) begin
                tries <= '0;
            end
        end
    end

    // ==============================================================
    //  COMBINACIONAL: Próximo estado
    // ==============================================================
    always_comb begin
        next = state;

        // Enquanto rst_sw alto, permanece em PROG (sem apagar registros)
        if (rst_on) begin
            next = PROG;
        end else begin
            unique case (state)
                PROG: begin
                    // Só sai para READY quando rst_sw=0 E senha completa digitada
                    if (idx == CODE_LEN) next = READY;
                    else                 next = PROG;
                end
                READY:  if (key_pressed_pulse) next = ENTRY;
                ENTRY:  if (idx == CODE_LEN)   next = VERIFY;
                VERIFY: begin
                    if      (attempt_code == pass_code) next = UNLOCK;
                    else if (tries == 2)                next = LOCKOUT; // vai virar 3ª falha
                    else                                 next = ERROR_P;
                end
                UNLOCK: next = UNLOCK;
                ERROR_P: if (err_cnt >= ERR_PULSE_CYCLES[$clog2(ERR_PULSE_CYCLES+1)-1:0]) next = READY;
                LOCKOUT: if (lock_cnt >= LOCK_CYCLES[$clog2(LOCK_CYCLES+1)-1:0])          next = READY;
                default: next = PROG;
            endcase
        end
    end

    // ==============================================================
    //  COMBINACIONAL: LEDs
    // ==============================================================
    localparam int ERR_CNT_MSB = $bits(err_cnt) - 1;

    always_comb begin
        LEDR = '0;
        LEDG = '0;

        // Progresso de digitação em PROG/ENTRY
        if ((state == PROG) || (state == ENTRY)) begin
            unique case (idx)
                0:       LEDG[3:0] = 4'b0000;
                1:       LEDG[3:0] = 4'b0001;
                2:       LEDG[3:0] = 4'b0011;
                3:       LEDG[3:0] = 4'b0111;
                default: LEDG[3:0] = 4'b1111;
            endcase
        end

        // Estado
        if (state == UNLOCK)  LEDG[8] = 1'b1;
        if (state == ERROR_P) LEDR[0] = err_cnt[ERR_CNT_MSB];
        if (state == LOCKOUT) LEDR[8] = 1'b1;
        if (state == PROG)    LEDG[7] = 1'b1;

        // Tentativas (2 bits → 3 LEDs)
        LEDR[3:1] = {1'b0, tries};
    end


endmodule
