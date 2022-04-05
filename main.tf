# terraform init - iniciar um projeto terraform
# terraform validate - verificar erros no arquivo
# terraform plan - verifica se possiu algo novo referente a nuvem igual o git add e commit
# terraform apply - sobe as informações do arquivo igual o git push


#qual a versão do terraform utilizada
terraform {
  required_version = ">= 0.13"

 required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {
    
  }
}

# Resource referente a um recurso a ser criado
# azurerm_resource_group qual o recurso no caso resource group
# rg-infra nome que vamos nos referenciar em outros resources
resource "azurerm_resource_group" "rg-infra" {
  name     = "atividade_infra"
  location = "westus2"
}

# Criando uma rede no meu rg
resource "azurerm_virtual_network" "vn-rede" {
  name                = "rede"
  # indico que é um rg.nomedoRG.atributo
  location            = azurerm_resource_group.rg-infra.location
  resource_group_name = azurerm_resource_group.rg-infra.name
  # IPs da rede
  address_space       = ["10.0.0.0/16"]
  # DNS da rede
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

}


resource "azurerm_subnet" "sub-rede" {
  name                 = "sub-rede"
  # Nome do RG que está associado
  resource_group_name  = azurerm_resource_group.rg-infra.name
  # Nome da rede que está associado
  virtual_network_name = azurerm_virtual_network.vn-rede.name
  address_prefixes     = ["10.0.1.0/24"]

}

# Criando um IP publico para ser acessado
resource "azurerm_public_ip" "pi_publico" {
  name                = "ip_publico"
  resource_group_name = azurerm_resource_group.rg-infra.name
  location            = azurerm_resource_group.rg-infra.location
  # tipo do IP: estatico ou dinâmico
  allocation_method   = "Static"

}

# Criando o Firewall
resource "azurerm_network_security_group" "nsg-firewall" {
  name                = "firewall"
  location            = azurerm_resource_group.rg-infra.location
  resource_group_name = azurerm_resource_group.rg-infra.name

  # cada um desses representa uma porta do firewall sendo aberta
  security_rule {
    name                       = "SSH"
    priority                   = 100 
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22" 
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Web"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Placa de rede
resource "azurerm_network_interface" "ni_placa_de_rede" {
  name                = "placa_de_rede"
  location            = azurerm_resource_group.rg-infra.location
  resource_group_name = azurerm_resource_group.rg-infra.name

  ip_configuration {
    name                          = "ip_placa"
    # Adicionar a sub-rede
    subnet_id                     = azurerm_subnet.sub-rede.id
    # IP dinâmico
    private_ip_address_allocation = "Dynamic"
    # Associar ip publico
    public_ip_address_id          = azurerm_public_ip.pi_publico.id
  }
}

# Associar sub-rede com o firewall
resource "azurerm_network_interface_security_group_association" "ass_network" {
  network_interface_id            = azurerm_network_interface.ni_placa_de_rede.id
  network_security_group_id       = azurerm_network_security_group.nsg-firewall.id
}



resource "azurerm_storage_account" "armazenamentoconta" {
  name                     = "sainfraarmaz"
  resource_group_name      = azurerm_resource_group.rg-infra.name
  location                 = azurerm_resource_group.rg-infra.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

}

# Criar a virtual machine
# az vm list-skus --location westus2 --size Standard_D --resource-type virtualMachines --output table
# comando para verificar quais máquinas estão disponiveis para cada região

resource "azurerm_linux_virtual_machine" "vmcomputer" {
  name                = "maquinavirtual"
  resource_group_name = azurerm_resource_group.rg-infra.name
  location            = azurerm_resource_group.rg-infra.location
  # Tipo de máquina
  size                  = "Standard_D2s_v5"
  network_interface_ids = [
    azurerm_network_interface.ni_placa_de_rede.id
  ]

  # Usuario e senha
  admin_username      = "adminuser"
  admin_password      = "Teste!23" 
  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                  = "disco"
    caching               = "ReadWrite"
    storage_account_type  = "Standard_LRS"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.armazenamentoconta.primary_blob_endpoint
  }

}


#criando uma variavel com o valor do IP publico
data "azurerm_public_ip" "dados_pip" {
  name = azurerm_public_ip.pi_publico.name
  resource_group_name = azurerm_resource_group.rg-infra.name
}

#acessar a máquina e executar comandos no terminal
resource "null_resource" "install-webserver" {

  # Conexão com com a máquina
  connection {
    type      = "ssh"
    host      = data.azurerm_public_ip.dados_pip.ip_address #ip publico
    user      = "adminuser"
    password  = "Teste!23" 
  }

  # Comandos que serão executados no terminal
  provisioner "remote-exec" {
    inline = [
      "cd ../..",
      "echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf > /dev/null",
      "sudo apt-get update",
      "sudo apt install -y apache2"
    ]
  }

  # Indica qual recurso precisa estar concluido para ele tentar executar esse
  depends_on = [
    azurerm_linux_virtual_machine.vmcomputer
  ]
}