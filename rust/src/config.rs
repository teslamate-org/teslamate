use envconfig::Envconfig;

#[derive(Envconfig, Default)]
pub struct Config {
    #[envconfig(from = "ADDOperandA", default = "1")]
    pub operand_a: i32,

    #[envconfig(from = "ADDOperandB", default = "2")]
    pub operand_b: i32,
}
