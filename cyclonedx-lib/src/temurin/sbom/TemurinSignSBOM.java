/**
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
*/
package temurin.sbom;

import org.webpki.json.JSONAsymKeySigner;
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
import java.util.Collections;
import java.util.List;
import java.security.GeneralSecurityException;
import java.security.KeyPair;

public class TemurinSignSBOM {

  static Bom signSBOM(String jsonFile, String pemFile) {
    try {
      // Read the JSON file to be signed
      Bom bom = readJSONfile(jsonFile);
      String sbomDataToSign = generateBomJson(bom);

      // Read the private key
      File privateKeyFile = new File(pemFile);
      byte[] privateKeyData = new byte[(int) privateKeyFile.length()];
      FileInputStream privateKeyFileInputStream = new FileInputStream(privateKeyFile);
      try {
        privateKeyFileInputStream.read(privateKeyData);
      } finally {
        privateKeyFileInputStream.close();
      }
      String privateKeyString = new String(privateKeyData, "UTF-8");
      KeyPair sampleKey = PEMDecoder.getKeyPair(privateKeyData);

      // Sign the JSON data
      String signedData = new JSONObjectWriter(JSONParser.parse(sbomDataToSign))
        .setSignature(new JSONAsymKeySigner(sampleKey.getPrivate()))
        .serializeToString(JSONOutputFormats.PRETTY_PRINT);

      JsonParser parser = new JsonParser();
      Bom signedBom = parser.parse(new StringReader(signedData));
      return signedBom;
    } catch (IOException | GeneralSecurityException | ParseException e) {
      e.printStackTrace();
    }
    return null;
  }
}
