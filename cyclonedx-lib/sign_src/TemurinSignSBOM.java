/*
 * ********************************************************************************
 * Copyright (c) 2023, 2024 Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made
 * available under the terms of the Apache Software License 2.0
 * which is available at https://www.apache.org/licenses/LICENSE-2.0.
 *
 * SPDX-License-Identifier: Apache-2.0
 * ********************************************************************************
 */

package temurin.sbom;

import org.cyclonedx.exception.GeneratorException;
import org.cyclonedx.generators.json.BomJsonGenerator;
import org.cyclonedx.model.Bom;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.Version;

import org.webpki.json.JSONAsymKeySigner;
import org.webpki.json.JSONObjectReader;
import org.webpki.json.JSONSignatureDecoder;
import org.webpki.json.JSONCryptoHelper;
import org.webpki.json.JSONAsymKeyVerifier;
import org.webpki.json.JSONObjectWriter;
import org.webpki.json.JSONOutputFormats;
import org.webpki.json.JSONParser;
import org.webpki.util.PEMDecoder;

import java.util.stream.Collectors;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.io.IOException;
import java.io.FileReader;
import java.io.FileWriter;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.PublicKey;
import org.cyclonedx.exception.ParseException;

import java.util.logging.Level;
import java.util.logging.Logger;

public final class TemurinSignSBOM {

    private static boolean verbose = false;

    // Create a logger for the class
    private static final Logger LOGGER = Logger.getLogger(TemurinSignSBOM.class.getName());

    private TemurinSignSBOM() {
    }

    /**
     * Main entry.
     * @param args Arguments for sbom operation.
     */
    public static void main(final String[] args) {
        String cmd = "";
        String privateKeyFile = null;
        String publicKeyFile = null;
        String fileName = null;
        boolean success = false; // add a new boolean success, default to false
        boolean privateStdIn = false; // TRUE if private key contents are passed in STDIN with --privateKeyFileSTDIN

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
            } else if (args[i].equals("--privateKeyFile")) {
                privateKeyFile = args[++i];
            } else if (args[i].equals("--privateKeyFileSTDIN")) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
                String privateKeyInput = reader.lines().collect(Collectors.joining("\n"));
                privateKeyFile = privateKeyInput;
                privateStdIn = true;
            } else if (args[i].equals("--publicKeyFile")) {
                publicKeyFile = args[++i];
            } else if (args[i].equals("--signSBOM")) {
                cmd = "signSBOM";
            } else if (args[i].equals("--verifySignature")) {
                cmd = "verifySignature";
            } else if (args[i].equals("--verbose")) {
                verbose = true;
            }
        }

        if (cmd.equals("signSBOM")) {
            Bom bom = signSBOM(fileName, privateKeyFile, privateStdIn);
            if (bom != null) {
                if (!writeJSONfile(bom, fileName)) {
                    success = false;
                }
            } else {
                success = false;
            }
            success = true; // set success to true only if signSBOM and writeJSONfile succeed
        } else if (cmd.equals("verifySignature")) {
            success = verifySignature(fileName, publicKeyFile); // set success to the result of verifySignature
            System.out.println("Signature verification result: " + (success ? "Valid" : "Invalid"));
        } else {
            System.out.println("Please enter a command.");
        }

        // Set success to true only when the operation is completed successfully.
        if (success) {
            System.out.println("Operation completed successfully.");
        } else {
            System.out.println("Operation failed.");
            System.exit(1);
        }
    }

    static Bom signSBOM(final String jsonFile, final String pemFile, final boolean privateStdIn) {
        try {
            // Read the JSON file to be signed
            Bom bom = readJSONfile(jsonFile);
            if (bom == null) {
                return null;
            }
            String sbomDataToSign;
            try {
                sbomDataToSign = generateBomJson(bom);
            } catch (GeneratorException e) {
                LOGGER.log(Level.SEVERE, "Exception generating BOM", e);
                return null;
            }

            // Read the private key
            KeyPair signingKey = null;
            if (privateStdIn) {
                // If private key is passed in STDIN
                signingKey = PEMDecoder.getKeyPair(pemFile.getBytes());
            } else {
                // If private key is a file
                signingKey = PEMDecoder.getKeyPair(Files.readAllBytes(Paths.get(pemFile)));
            }

            // Sign the JSON data
            String signedData = new JSONObjectWriter(JSONParser.parse(sbomDataToSign))
                    .setSignature(new JSONAsymKeySigner(signingKey.getPrivate()))
                    .serializeToString(JSONOutputFormats.PRETTY_PRINT);

            JsonParser parser = new JsonParser();
            Bom signedBom = parser.parse(new StringReader(signedData));
            return signedBom;
        } catch (IOException | GeneralSecurityException | ParseException e) {
            LOGGER.log(Level.SEVERE, "Error signing SBOM", e);
            return null;
        }
    }

    static String generateBomJson(final Bom bom) throws GeneratorException {
        BomJsonGenerator bomGen = new BomJsonGenerator(bom, Version.VERSION_16);
        String json = bomGen.toJsonString();
        return json;
    }

    static boolean writeJSONfile(final Bom bom, final String fileName) {
        // Creates testJson.json file
        String json;
        try {
            json = generateBomJson(bom);
        } catch (GeneratorException e) {
            LOGGER.log(Level.SEVERE, "Exception generating BOM", e);
            return false;
        }

        try (FileWriter file = new FileWriter(fileName)) {
            file.write(json);
            return true;
        } catch (IOException e) {
            LOGGER.log(Level.SEVERE, "Error writing JSON file " + fileName, e);
            return false;
        }
    }

    static Bom readJSONfile(final String fileName) {
        try (FileReader reader = new FileReader(fileName)) {
            JsonParser parser = new JsonParser();
            return parser.parse(reader);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error reading JSON file " + fileName, e);
        }
        return null;
    }

    static boolean verifySignature(final String jsonFile, final String publicKeyFile) {
        try {
            // Read the JSON file to be verified
            Bom bom = readJSONfile(jsonFile);
            String signedSbomData;
            try {
                signedSbomData = generateBomJson(bom);
            } catch (GeneratorException e) {
                LOGGER.log(Level.SEVERE, "Exception generating BOM", e);
                return false;
            }

            // Parse JSON
            JSONObjectReader reader = JSONParser.parse(signedSbomData);

            // Load public key from file
            PublicKey publicKey = PEMDecoder.getPublicKey(Files.readAllBytes(Paths.get(publicKeyFile)));

            // Verify signature using the loaded public key
            JSONSignatureDecoder signature = reader.getSignature(new JSONCryptoHelper.Options());
            signature.verify(new JSONAsymKeyVerifier(publicKey));
            return true;
        } catch (IOException | GeneralSecurityException e) {
            LOGGER.log(Level.SEVERE, "Exception verifying json signature", e);
            return false;
        }
    }
}
