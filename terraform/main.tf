resource "local_file" "output" {
  content = <<EOF
This is a test
EOF

  filename = "../test.txt"
}
