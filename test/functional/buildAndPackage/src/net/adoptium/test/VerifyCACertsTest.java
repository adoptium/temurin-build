/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package net.adoptium.test;

import org.testng.annotations.Test;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyStore;
import java.util.logging.Logger;
import static net.adoptium.test.JdkVersion.getJavaHome;

import static org.testng.Assert.assertEquals;


/**
 * Tests whether keytool has correct number of certificates imported.
 */
@Test(groups = {"level.extended"})
public class VerifyCACertsTest {

    // config logger
    private static final Logger LOGGER = Logger.getLogger(VerifyCACertsTest.class.getName());

    private static final JdkVersion JDK_VERSION = new JdkVersion();

    // Expect matching certs number
    private static final int EXPECTED_COUNT = 143;

    /* TODO: add up to 141 certs
    private static final Map<String, String> EXPFP_MAP = new HashMap<>() {
        put("amazonrootca1 [jdk]",          "8E:CD:E6:88:4F:3D:87:B1:12:5B:A3:1A:C3:FC:B1:3D:70:16:DE:7F:57:CC:90:4F:E1:CB:97:C6:AE:98:19:6E");
        put("amazonrootca2 [jdk]",          "1B:A5:B2:AA:8C:65:40:1A:82:96:01:18:F8:0B:EC:4F:62:30:4D:83:CE:C4:71:3A:19:C3:9C:01:1E:A4:6D:B4");
        put("amazonrootca3 [jdk]",          "18:CE:6C:FE:7B:F1:4E:60:B2:E3:47:B8:DF:E8:68:CB:31:D0:2E:BB:3A:DA:27:15:69:F5:03:43:B4:6D:B3:A4");
        put("amazonrootca4 [jdk]",          "E3:5D:28:41:9E:D0:20:25:CF:A6:90:38:CD:62:39:62:45:8D:A5:C6:95:FB:DE:A3:C2:2B:0B:FB:25:89:70:92");
        put("godaddyrootg2ca [jdk]",        "45:14:0B:32:47:EB:9C:C8:C5:B4:F0:D7:B5:30:91:F7:32:92:08:9E:6E:5A:63:E2:74:9D:D3:AC:A9:19:8E:DA");
        put("godaddyclass2ca [jdk]",        "C3:84:6B:F2:4B:9E:93:CA:64:27:4C:0E:C6:7C:1E:CC:5E:02:4F:FC:AC:D2:D7:40:19:35:0E:81:FE:54:6A:E4");
        put("digicertglobalrootca [jdk]",   "43:48:A0:E9:44:4C:78:CB:26:5E:05:8D:5E:89:44:B4:D8:4F:96:62:BD:26:DB:25:7F:89:34:A4:43:C7:01:61");
        put("digicertglobalrootg2 [jdk]",   "CB:3C:CB:B7:60:31:E5:E0:13:8F:8D:D3:9A:23:F9:DE:47:FF:C3:5E:43:C1:14:4C:EA:27:D4:6A:5A:B1:CB:5F");
        put("digicertglobalrootg3 [jdk]",   "31:AD:66:48:F8:10:41:38:C7:38:F3:9E:A4:32:01:33:39:3E:3A:18:CC:02:29:6E:F9:7C:2A:C9:EF:67:31:D0");
        put("digicerttrustedrootg4 [jdk]",  "55:2F:7B:DC:F1:A7:AF:9E:6C:E6:72:01:7F:4F:12:AB:F7:72:40:C7:8E:76:1A:C2:03:D1:D9:D2:0A:C8:99:88");
        put("digicertassuredidrootca [jdk]","3E:90:99:B5:01:5E:8F:48:6C:00:BC:EA:9D:11:1E:E7:21:FA:BA:35:5A:89:BC:F1:DF:69:56:1E:3D:C6:32:5C");
        put("digicertassuredidg2 [jdk]",    "7D:05:EB:B6:82:33:9F:8C:94:51:EE:09:4E:EB:FE:FA:79:53:A1:14:ED:B2:F4:49:49:45:2F:AB:7D:2F:C1:85");
        put("digicertassuredidg3 [jdk]",    "7E:37:CB:8B:4C:47:09:0C:AB:36:55:1B:A6:F4:5D:B8:40:68:0F:BA:16:6A:95:2D:B1:00:71:7F:43:05:3F:C2");
        put("digicerthighassuranceevrootca [jdk]", "74:31:E5:F4:C3:C1:CE:46:90:77:4F:0B:61:E0:54:40:88:3B:A9:A0:1E:D0:0B:A6:AB:D7:80:6E:D3:B1:18:CF");
    }

    private static final HexFormat HEX = HexFormat.ofDelimiter(":").withUpperCase();
    */
    private static final String JAVA_HOME = getJavaHome();
    // concat absolute path regardless OS
    private static final String CACERTS = JAVA_HOME + File.separator + "lib" + File.separator + "security" + File.separator + "cacerts";

    /**
     * Verifies the number of certs matching EXPCOUNT.
     */
    @Test
    public void isCertNrMatch() throws Exception {
        LOGGER.info("cacerts file: " + CACERTS);
        try {
            byte[] data = Files.readAllBytes(Paths.get(CACERTS));  //Path.of introduced after jdk8

            KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType()); // fallback to JKS if not set defaulttype
            ks.load(new ByteArrayInputStream(data), "changeit".toCharArray());
            assertEquals(ks.size(), EXPECTED_COUNT, "Failed to match CA certs number.");
        } catch (Exception e) {
            throw new Exception("Failed to test certs number", e);
        }
    }

    /*
    TODO: enable test when EXPFP_MAP is complete
    TODO: import java.util.HexFormat;
    TODO: import java.security.cert.X509Certificate;
    TODO: import static org.testng.Assert.assertTrue;
    Verifies fingerprints of certs matching EXPFP_MAP.
    @Test
    public void isCertContentMatch() throws xception {
        LOGGER.info("cacerts file: " + CACERTS);
        static MessageDigest md = MessageDigest.getInstance("SHA-256");
        try {
            byte[] data = Files.readAllBytes(Path.of(CACERTS));

            KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
            ks.load(new ByteArrayInputStream(data), "changeit".toCharArray());

            for (String alias : EXPFP_MAP.keySet()) {
                // check alias is there
                assertTrue(ks.isCertificateEntry(alias));

                String fingerprint = EXPFP_MAP.get(alias);
                X509Certificate cert = (X509Certificate) ks.getCertificate(alias);
                byte[] digest = md.digest(cert.getEncoded());
                // check fingerprint is there
                assertTrue(fingerprint.equals(HEX.formatHex(digest));
        } catch (Exception e) {
            throw new Exception("Failed to test certs' content", e);
        }
    }
    */
}
