/**
 * # Licensed under the Apache License, Version 2.0 (the "License");
 * # you may not use this file except in compliance with the License.
 * # You may obtain a copy of the License at
 * #
 * #      https://www.apache.org/licenses/LICENSE-2.0
 * #
 * # Unless required by applicable law or agreed to in writing, software
 * # distributed under the License is distributed on an "AS IS" BASIS,
 * # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * # See the License for the specific language governing permissions and
 * # limitations under the License.
 * ################################################################################
 */
package temurin.sbom;

import org.cyclonedx.BomGeneratorFactory;
import org.cyclonedx.CycloneDxSchema;
import org.cyclonedx.generators.json.BomJsonGenerator;
import org.cyclonedx.model.Bom;
import org.cyclonedx.parsers.JsonParser;

import org.webpki.json.JSONAsymKeySigner;
import org.webpki.json.JSONObjectReader;
import org.webpki.json.JSONSignatureDecoder;
import org.webpki.json.JSONCryptoHelper;
import org.webpki.json.JSONAsymKeyVerifier;
import org.webpki.json.JSONObjectWriter;
import org.webpki.json.JSONOutputFormats;
import org.webpki.json.JSONParser;
import org.webpki.util.PEMDecoder;

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
        String cmd = null;
        String privateKeyFile = null;
        String publicKeyFile = null;
        String fileName = null;
        boolean success = false; // add a new boolean success, default to false

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
            } else if (args[i].equals("--privateKeyFile")) {
                privateKeyFile = args[++i];
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
            Bom bom = signSBOM(fileName, privateKeyFile);
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
        }

        // Set success to true only when the operation is completed successfully.
        if (success) {
            System.out.println("Operation completed successfully.");
        } else {
            System.out.println("Operation failed.");
        }
    }

    static Bom signSBOM(final String jsonFile, final String pemFile) {
        try {
            // Read the JSON file to be signed
            Bom bom = readJSONfile(jsonFile);
            if (bom == null) {
                return null;
            }
            String sbomDataToSign = generateBomJson(bom);

            // Read the private key
            KeyPair signingKey = PEMDecoder.getKeyPair(Files.readAllBytes(Paths.get(pemFile)));

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

    static String generateBomJson(final Bom bom) {
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(CycloneDxSchema.Version.VERSION_14, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static boolean writeJSONfile(final Bom bom, final String fileName) {
        // Creates testJson.json file
        String json = generateBomJson(bom);
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
            String signedSbomData = generateBomJson(bom);

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
        }
        return false;
    }
}
