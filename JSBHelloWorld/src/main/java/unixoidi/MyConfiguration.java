package unixoidi;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.servers.Server;
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class MyConfiguration {
    
    @Bean
  public OpenAPI myOpenAPI() {
    Server devServer = new Server();
    devServer.setUrl("http://localhost:8080");
    devServer.setDescription("Razvoj (DEV)");

    Server prodServer = new Server();
    prodServer.setUrl("https://jsb.unixoidi.xyz");
    prodServer.setDescription("Produkcija (PROD)");

    
    return new OpenAPI().servers(List.of(devServer, prodServer));
  }
}