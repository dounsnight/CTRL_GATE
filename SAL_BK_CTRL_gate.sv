`include "TIME_SCALE.svh"
`include "SAL_DDR_PARAMS.svh"
//This is for the gated SR latch module.

module SAL_BK_CTRL_GATELEVEL
#(
    parameter                   BK_ID   = 0
)
(
    // clock & reset
    input                       clk,
    input                       rst_n,

    // timing parameters
    TIMING_IF.MON               timing_if,

    // request from the address decoder
    REQ_IF.DST                  req_if,

    // scheduling interface
    output  logic               act_req_o,
    output  logic               rd_req_o,
    output  logic               wr_req_o,
    output  logic               pre_req_o,
    output  logic               ref_req_o,
    output  dram_ra_t           ra_o,
    output  dram_ca_t           ca_o,
    output  axi_id_t            id_o,
    output  axi_len_t           len_o,
    output  seq_num_t           seq_num_o,

    input   wire                act_gnt_i,
    input   wire                rd_gnt_i,
    input   wire                wr_gnt_i,
    input   wire                pre_gnt_i,
    input   wire                ref_gnt_i,

    // per-bank auto-refresh requests
    input   wire                ref_req_i,
    output  logic               ref_gnt_o
);

    // current row address
    dram_ra_t                   cur_ra,             cur_ra_n;

    wire                        is_t_rc_met,
                                is_t_ras_met,
                                is_t_rcd_met,
                                is_t_rp_met,
                                is_t_rtp_met,
                                is_t_wtp_met,
                                is_burst_cycle_met,
                                is_t_rfc_met,
                                is_row_open_met;
                                
                                                       

    // tried to make similar to the state machine
    // in the Micron dataset. Can eliminate some states
    enum    logic   [2:0]   {
        S_IDLE                  = 'd0,
        S_ACTIVATING            = 'd1,
        S_BANK_ACTIVE           = 'd2,
        S_READING               = 'd3,
        S_WRITING               = 'd4,
        S_PRECHARGING           = 'd5,
        S_REFRESHING            = 'd6
    } state,    state_n;

    always_ff @(posedge clk)
        if (~rst_n) begin
            state                   <= S_IDLE;
            cur_ra                  <= 'h0;
        end
        else begin
            state                   <= state_n;
            cur_ra                  <= cur_ra_n;
        end

    always_comb begin
        cur_ra_n                    = cur_ra;
        state_n                     = state;

        ref_gnt_o                   = 1'b0;
        req_if.ready                = 1'b0;

        act_req_o                   = 1'b0;
        rd_req_o                    = 1'b0;
        wr_req_o                    = 1'b0;
        pre_req_o                   = 1'b0;
        ref_req_o                   = 1'b0;
        ra_o                        = 'hx;
        ca_o                        = 'hx;
        id_o                        = 'hx;
        len_o                       = 'hx;
    end
    wire IDLE;
    wire ACTIVATING;
    wire BANKACTIVE;
    wire WRITING;
    wire READING;
    wire PRECHARGING;
    wire REFRESHING;
    wire DEFAULT;
    wire wire_id_act_gnt;
    wire wire_ac;
    wire wire_wr;
    wire wire_rd;
    wire wire_pr;
    wire wire_rf;
    wire wire_ba_valid;
    wire cur_ra_not;
    wire req_ra_not;
    wire wire_eq_and_1;
    wire wire_eq_and_2;
    wire ba_eq_ra;
    wire wire_ba_eq;
    wire wire_ba_wr;
    wire wire_ba_wr_last;
    wire req_wr_not;
    wire wire_ba_rd;
    wire wire_ba_rd_last;
    wire wr_req_o;

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                         IDLE                                                                             //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND3    id_act_req      (.A1(IDLE), .A2(req_if.valid), .A3(is_t_rc_met), .Y(act_req_o));             //assign act_req_o
    AND2    id_act_gnt      (.A1(act_req_0), .A2(act_gnt_i), Y(wire_id_act_gnt));                        //assign_wire_id_act_gnt 

    MUX21   id_state_1      (.A1(1'b1), .A2(1'b0), .S0(wire_id_act_gnt), .Y(ACTIVATING));                // ACTIVATING set
    MUX21   id_state_2      (.A1(1'b0), .A2(1'b1), .S0(wire_id_act_gnt), .Y(IDLE));                      // IDLE set

    DFF     id_ff_cur_ra    (.D(req_if.ra), .RST_n(act_req_o), .CLK(clk), .Q(ra_o), .QN());              // ra_o = req_if.ra
    DFF     id_ff_cur_ra    (.D(req_if.ra), .RST_n(act_req_o), .CLK(clk), .Q(seq_num_o), .QN());         // seq_num = req_if.seq_num
    DFF     id_ff_cur_ra    (.D(req_if.ra), .RST_n(wire_id_act_gnt), .CLK(clk), .Q(cur_ra_n), .QN());    // cur_ra_n = req_if.ra

    AND3    id_ref_req      (.A1(IDLE), .A2(ref_req_i), .A3(is_t_rc_met), .Y(ref_req_o));                //assign ref_req_o
    AND2    id_ref_gnt      (.A1(ref_req_0), .A2(ref_gnt_i), Y(ref_gnt_o));                              //assign ref_gnt_i

    MUX21   id_state_3      (.A1(1'b1), .A2(1'b0), .S0(ref_gnt_o), .Y(REFRESHING));                      // REFRESHING set
    MUX21   id_state_4      (.A1(1'b0), .A2(1'b1), .S0(ref_gnt_o), .Y(IDLE));                            // IDLE set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                      ACTIVATING                                                                          //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    ac_1            (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_ac));                            // assign wire_ac

    MUX21   ac_state_1      (.A1(1'b1), .A2(1'b0), .S0(wire_ac), .Y(BANKACTIVE));                        // BANKACTIVE set
    MUX21   ac_state_2      (.A1(1'b0), .A2(1'b1), .S0(wire_ac), .Y(ACTIVATING));                        // ACTIVATING set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                      BANK_ACTIVE                                                                         //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    ba_valid        (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_ba_valid));                      // assign wire_ba_valid

    // equivant gate begin
    INV     ba_eq_inv_1     (.A(cur_ra), .Y(cur_ra_not));                                                // assign cur_ra_not
    INV     ba_eq_inv_2     (.A(req_if.ra), .Y(req_ra_not));                                             // assign req_ra_not
    AND2    ba_eq_and_1     (.A1(cur_ra), .A2(req_if.ra), Y(wire_eq_and_1));                             // assign wire_eq_and_1
    AND2    ba_eq_and_2     (.A1(cur_ra_not), .A2(req_ra_not), Y(wire_eq_and_2));                        // assign wire_eq_and_2
    OR2     ba_eq_or_1      (.A1(wire_eq_and_1), .A2(wire_eq_and_2), .Y(ba_eq_ra));                      // assign ra_equivalent
    // equivalent gate end

    AND2    ba_and_eq       (.A1(wire_ba_valid), .A2(ba_eq_ra), Y(wire_ba_eq));                          // assign wire_ba_eq
    AND2    ba_wr           (.A1(req_if.ra), .A2(wire_ba_eq), Y(wire_ba_wr));                            // assign wire_ba_wr
    AND2    ba_wr_gnt       (.A1(wr_gnt_i), .A2(wire_ba_wr), Y(wire_ba_wr_last));                        // assign wire_ba_wr_last

    INV     ba_wr_inv       (.A(req_if.ra), .Y(req_wr_not));                                             // assign req_wr_not

    AND2    ba_rd           (.A1(wire_ba_eq), .A2(req_wr_not), Y(wire_ba_rd));                           // assign wire_ba_rd
    AND2    ba_rd_gnt       (.A1(rd_gnt_i), .A2(wire_ba_rd), Y(wire_ba_rd_last));                        // assign wire_ba_rd_last

    MUX21   ba_state_1      (.A1(1'b1), .A2(1'b0), .S0(wire_ba_wr_last), .Y(WRITING));                   // WRITING set
    MUX21   ba_state_2      (.A1(1'b0), .A2(1'b1), .S0(wire_ba_wr_last), .Y(BANKACTIVE));                // BANKACTIVE set

    DFF     ba_ff_ca_o      (.D(req_if.ca), .RST_n(wire_ba_eq), .CLK(clk), .Q(ca_o), .QN());             // ca_o = req_if.ca
    DFF     ba_ff_id_o      (.D(req_if.id), .RST_n(wire_ba_eq), .CLK(clk), .Q(id_o), .QN());             // id_o = req_if.id
    DFF     ba_ff_len_o     (.D(req_if.len), .RST_n(wire_ba_eq), .CLK(clk), .Q(len_o), .QN());           // len_o = req_if.len
    DFF     ba_ff_seq_o     (.D(req_if.seq_num), .RST_n(wire_ba_eq), .CLK(clk), .Q(seq_num_o), .QN());   // seq_num_o = req_if.seq_num

    MUX21   ba_wr_req       (.A1(1'b1), .A2(1'b0), .S0(wire_ba_wr), .Y(wr_req_o));                       // wr_req_o set
    MUX21   ba_wr_ready     (.A1(1'b1), .A2(1'b0), .S0(wire_ba_wr_last), .Y(req_if.ready));              // req_if.ready set

    MUX21   ba_state_3      (.A1(1'b1), .A2(1'b0), .S0(wire_ba_rd_last), .Y(READING));                   // READING set
    MUX21   ba_state_4      (.A1(1'b0), .A2(1'b1), .S0(wire_ba_rd_last), .Y(BANKACTIVE));                // BANKACTIVE set

    MUX21   ba_rd_req       (.A1(1'b1), .A2(1'b0), .S0(wire_ba_rd), .Y(rd_req_o));                       // rd_req_o set
    MUX21   ba_rd_ready     (.A1(1'b1), .A2(1'b0), .S0(wire_ba_rd_last), .Y(req_if.ready));              // req_if.ready set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                        WRITING                                                                           //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    wr_1           (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_wr));                             // assign wire_ac

    MUX21   wr_state_1     (.A1(1'b1), .A2(1'b0), .S0(wire_wr), .Y(BANKACTIVE));                         // BANKACTIVE set
    MUX21   wr_state_2     (.A1(1'b0), .A2(1'b1), .S0(wire_wr), .Y(WRITING));                            // WRITING set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                        READING                                                                           //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    rd_1           (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_rd));                             // assign wire_ac

    MUX21   rd_state_1     (.A1(1'b1), .A2(1'b0), .S0(wire_rd), .Y(BANKACTIVE));                         // BANKACTIVE set
    MUX21   rd_state_2     (.A1(1'b0), .A2(1'b1), .S0(wire_rd), .Y(READING));                            // READING set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                      PRECHARGING                                                                         //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    pr_1           (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_pr));                             // assign wire_ac

    MUX21   pr_state_1     (.A1(1'b1), .A2(1'b0), .S0(wire_pr), .Y(IDLE));                               // IDLE set
    MUX21   pr_state_2     (.A1(1'b0), .A2(1'b1), .S0(wire_pr), .Y(PRECHARGING));                        // PRECHARGING set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                       REFRESHING                                                                         //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    AND2    rf_1           (.A1(ACTIVATING), .A2(is_t_rrd_met), Y(wire_rf));                             // assign wire_ac

    MUX21   rf_state_1     (.A1(1'b1), .A2(1'b0), .S0(wire_rf), .Y(IDLE));                               // IDLE set
    MUX21   rf_state-2     (.A1(1'b0), .A2(1'b1), .S0(wire_rf), .Y(REFRESHING));                         // REFRESHING set

//----------------------------------------------------------------------------------------------------------------------------------------------------------//
//                                                                       TIMING_CNTR                                                                        //
//----------------------------------------------------------------------------------------------------------------------------------------------------------//

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RC_WIDTH)) u_rc_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (act_gnt_i),
        .reset_value_i              (timing_if.t_rc_m1),
        .is_zero_o                  (is_t_rc_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RAS_WIDTH)) u_ras_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (act_gnt_i),
        .reset_value_i              (timing_if.t_ras_m1),
        .is_zero_o                  (is_t_ras_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RCD_WIDTH)) u_rcd_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (act_gnt_i),
        .reset_value_i              (timing_if.t_rcd_m2),
        .is_zero_o                  (is_t_rcd_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RP_WIDTH)) u_rp_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (pre_gnt_i),
        .reset_value_i              (timing_if.t_rp_m2),
        .is_zero_o                  (is_t_rp_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RTP_WIDTH)) u_rtp_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (rd_gnt_i),
        .reset_value_i              (timing_if.t_rtp_m1),
        .is_zero_o                  (is_t_rtp_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_WTP_WIDTH)) u_wtp_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (wr_gnt_i),
        .reset_value_i              (timing_if.t_wtp_m1),
        .is_zero_o                  (is_t_wtp_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`BURST_CYCLE_WIDTH)) u_burst_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (rd_gnt_i | wr_gnt_i),
        .reset_value_i              (timing_if.burst_cycle_m2),
        .is_zero_o                  (is_burst_cycle_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`T_RFC_WIDTH)) u_rfc_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (ref_gnt_i),
        .reset_value_i              (timing_if.t_rfc_m2),
        .is_zero_o                  (is_t_rfc_met)
    );

    SAL_TIMING_CNTR  #(.CNTR_WIDTH(`ROW_OPEN_WIDTH)) u_row_open_cnt
    (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reset_cmd_i                (rd_gnt_i | wr_gnt_i),
        .reset_value_i              (timing_if.row_open_cnt),
        .is_zero_o                  (is_row_open_met)
    );

endmodule // SAL_BK_CTRL
