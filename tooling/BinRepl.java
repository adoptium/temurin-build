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

import java.util.HexFormat;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.Files;
import java.io.FileOutputStream;

/**
 * This class binary replaces the given "hex" binary values with a new value.
 */
class BinRepl {

    // A simple static counter
    static int replCounter = 0;

    public static void main(String[] args) throws Exception {
        String inFile = null;
        String outFile = null;

        String[] hex = null;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--inFile")) {
                inFile = args[++i];
            } else if (args[i].equals("--outFile")) {
                outFile = args[++i];
            } else if (args[i].equals("--hex")) {
                hex = args[++i].split("-");
            } else {
                System.out.println("Unknown option: "+args[i]);
                System.exit(1);
            }
        }

        if (inFile == null || outFile == null || hex == null) {
            System.out.println("Missing option, syntax:");
            System.out.println("BinRepl --inFile path --outFile path --hex aa:aa-bb:bb");
            System.exit(1);
        }

        HexFormat hexformat = HexFormat.ofDelimiter(":");
        byte[] binA = hexformat.parseHex(hex[0]);
        byte[] binB = hexformat.parseHex(hex[1]);

        byte[] inBytes = Files.readAllBytes(Paths.get(inFile));

        byte[] outBytes = bin_replace(inBytes, binA, binB);
        if (outBytes == null) {
            System.out.println("replacement hex not found in: "+inFile);
            System.exit(1);
        } else {
            System.out.println("Number of occurrences of "+hex[0]+" replaced with "+hex[1]+" = "+replCounter);
        }

        try(FileOutputStream fos = new FileOutputStream(outFile)) {
            fos.write(outBytes);
        } 
    }

    // Replace byte[] x with y in b1 and return new array b2
    static byte[] bin_replace(byte[] b1, byte[] x, byte[] y) {
        byte[] b2 = new byte[b1.length+4096]; // 4096 extra should be plenty!
        boolean found = false; // A match was found to replace

        int buf = x.length;
        int i2 = 0;
        for(int i1=0; i1<b1.length; i1++) {
            boolean match = true;
            if ((i1+buf) > b1.length) {
                match = false;
            } else {
                for(int j=0; j<buf; j++) {
                    if (b1[i1+j] != x[j]) {
                        match = false;
                        break;
                    }
                }
            }
            if (match) {
                found = true;
                replCounter++;
                for(int j=0; j<y.length; j++) {
                    b2[i2+j] = y[j];
                }
                i1 += (buf-1);
                i2 += (y.length-1);
            } else {
                b2[i2] = b1[i1];
            }
            i2++;
        }

        if (found) {
            // Create return array
            byte[] replaced = new byte[i2];
            System.arraycopy(b2, 0, replaced, 0, i2);
            return replaced;
        } else {
            return null;
        }
    }
}

