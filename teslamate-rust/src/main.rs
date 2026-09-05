fn main() {
    let result = add(1, 2);
    println!("add(1, 2) = {result}");
}

const fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod test {
    use super::add;

    #[test]
    fn test_add() {
        assert_eq!(add(1, 2), 3);
    }
}
