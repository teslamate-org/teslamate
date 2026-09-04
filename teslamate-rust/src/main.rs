fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
use super::*;

    #[test]
    fn test_main() {
        main();
        assert_eq!(1, 1);
    }
}
