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

import java.io.File;
import java.io.FileInputStream;
import java.io.StringReader;
import java.io.IOException;
import java.io.FileReader;
import java.io.FileWriter;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.PublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.logging.Logger;
import java.util.Base64;

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
    public static void main(final String[] args) throws Exception {
        String cmd = null;
        String privateKeyFile = null;
        String publicKeyFile = null;
        String fileName = null;

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
            writeJSONfile(bom, fileName);
        } else if (cmd.equals("verifySignature")) {
            boolean isValid = verifySignature(fileName, publicKeyFile);
            System.out.println("Signature verification result: " + (isValid ? "Valid" : "Invalid"));
            if (!isValid) {
                System.exit(1);
            }
        }
    }

    static Bom signSBOM(final String jsonFile, final String pemFile) throws IOException, GeneralSecurityException, ParseException {
        try {
            // Read the JSON file to be signed
            Bom bom = readJSONfile(jsonFile);
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
        } catch (IOException | GeneralSecurityException | org.cyclonedx.exception.ParseException e) {
            // Log the exception with the logger
            LOGGER.severe("An error occurred while signing the SBOM: " + e.getMessage());
            e.printStackTrace();
        }
        return null;
    }

    static String generateBomJson(final Bom bom) {
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(CycloneDxSchema.Version.VERSION_14, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static void writeJSONfile(final Bom bom, final String fileName) {
        // Creates testJson.json file
        FileWriter file;
        String json = generateBomJson(bom);
        try {
            file = new FileWriter(fileName);
            file.write(json);
            file.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    static Bom readJSONfile(final String fileName) {                                 // Returns parse bom
        Bom bom = null;
        try {
            FileReader reader = new FileReader(fileName);
            JsonParser parser = new JsonParser();
            bom = parser.parse(reader);
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            return bom;
        }
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
            System.out.println("Exception verifying json signature: " + e);
        }
        return false;
    }
}
