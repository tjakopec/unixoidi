/*
 * Click nbfs://nbhost/SystemFileSystem/Templates/Licenses/license-default.txt to change this license
 * Click nbfs://nbhost/SystemFileSystem/Templates/Classes/Class.java to edit this template
 */
package unixoidi;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 *
 * @author Korisnik
 */
@RestController
@RequestMapping("/api/v1/primjer")
public class PrimjerController {
    
    
    @GetMapping("/get")
    public ResponseEntity<String> get(){
        return new ResponseEntity<>("Hello world",HttpStatus.OK);
    }
    
    
    @PostMapping("/post")
    public ResponseEntity<String> post(
    @RequestParam (required = true) String naziv,
    @RequestParam (required = false) int broj
    ){
        return new ResponseEntity<>("Primio " + naziv + " i " + broj,HttpStatus.CREATED);
    }
    
    @PutMapping("/put")
    public ResponseEntity<String> put(
    @RequestParam (required = true) int sifra,
    @RequestParam (required = true) String naziv,
    @RequestParam (required = false) int broj
    ){
        return new ResponseEntity<>("Promjenjeno "+ naziv + " i " + broj + " na " + sifra,HttpStatus.OK);
    }
    
     @DeleteMapping("/delete")
    public ResponseEntity<String> delete(
    @RequestParam (required = true) int sifra
    ){
        return new ResponseEntity<>("Obrisano " + sifra,HttpStatus.OK);
    }
    
}
