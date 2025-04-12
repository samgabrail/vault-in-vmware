job "nginx_web_server" {
  datacenters = ["dc1"]
  type = "service"

  group "nginx" {
    count = 1

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:latest"
        port_map {
          http = 80
        }
      }

      resources {
        network {
          port "http" {
            static = 80
          }
        }
      }

      service {
        name = "nginx"
        port = "http"
        check {
          name = "http"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }
    }
  }
}
