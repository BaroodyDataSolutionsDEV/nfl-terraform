// output the public ip of the web server
output "bastion_public_ip" {
    description = "Public IP address of the bastion server"
    value = aws_eip.warehouse_bastion_eip[0].public_ip
    depends_on = [aws_eip.warehouse_bastion_eip]
}

// output the public DNS address of the bastion server
output "bastion_public_dns" {
    description = "The public DNS address of the bastion server"
    value = aws_eip.warehouse_bastion_eip[0].public_dns
    depends_on = [aws_eip.warehouse_bastion_eip]
}

// output the database endpoint
output "database_endpoint" {
    description = "The endpoint of the database"
    value = aws_db_instance.warehouse_database.address
}

// output the database port
output "database_port" {
    description = "The port of the database"
    value = aws_db_instance.warehouse_database.port
}