import java.util.HexFormat;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.Files;
import java.io.FileOutputStream;

class WinVersionInfoDel {

    public static void main(String[] args) throws Exception {
        String inFile = null;
        String outFile = null;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--inFile")) {
                inFile = args[++i];
            } else if (args[i].equals("--outFile")) {
                outFile = args[++i];
            } else {
                System.out.println("Unknown option: "+args[i]);
                System.exit(1);
            }
        }

        if (inFile == null || outFile == null) {
            System.out.println("Missing option, syntax:");
            System.out.println("WinVersionInfoDel --inFile path --outFile path");
            System.exit(1);
        }

        byte[] inBytes = Files.readAllBytes(Paths.get(inFile));

        byte[] outBytes = del_versionInfo(inBytes);
        if (outBytes == null) {
            System.out.println("VS_VERSION_INFO not found in: "+inFile);
            System.exit(1);
        }

        try(FileOutputStream fos = new FileOutputStream(outFile)) {
            fos.write(outBytes);
        } 
    }

    // Delete VS_VERSION_INFO from b1
    static byte[] del_versionInfo(byte[] b1) throws Exception {
        byte[] b2 = new byte[b1.length+4096]; // 4096 extra should be plenty!
        boolean found = false; // A match was found to replace

        HexFormat hex = HexFormat.ofDelimiter(":");

        // See https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations

        // Create searchKey for VS_VERSION_INFO containing the key and first bit of structure
        // The key starts from after the 2 byte structure length
        byte[] searchKey = new byte[256];
        int keylen=0;

        // WORD wValueLength
        System.arraycopy(hex.parseHex("34:00"), 0, searchKey, keylen, 2);
        keylen += 2;

        // WORD wType
        System.arraycopy(hex.parseHex("00:00"), 0, searchKey, keylen, 2);
        keylen += 2;

        // VS_VERSION_INFO szKey
        byte[] szKey = "VS_VERSION_INFO".getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, searchKey, keylen, szKey.length);
        keylen += szKey.length;
        // "sz" zero termination
        searchKey[keylen++] = 0;
        searchKey[keylen++] = 0;

        // WORD Padding1 32bit boundary
        int pad = 4-((keylen+2) % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) searchKey[keylen++] = 0;
        }

        // DWORD dwSignature of vs_fixedfileinfo
        System.arraycopy(hex.parseHex("BD:04:EF:FE"), 0, searchKey, keylen, 4);
        keylen += 4;

        // That should be enough of a "searchKey"

        // Find searchKey in b1 and skip the vs_version_info being copied to return array
        int i2 = 0;
        for(int i1=0; i1<b1.length; i1++) {
            boolean match = true;
            if ((i1+keylen) > b1.length) {
                match = false;
            } else {
                for(int j=0; j<keylen; j++) {
                    if (b1[i1+j] != searchKey[j]) {
                        match = false;
                        break;
                    }
                }
            }
            if (match) {
                found = true;
                // Get the vs_info_len from the previous 2 bytes
                int vs_info_len = ((int)b1[i1-2]) + (((int)b1[i1-1])*0x100);
                // Skip the vs_version_info
                i1 += (vs_info_len-2);
                i2 -= 2;
            } else {
                b2[i2] = b1[i1];
            }
            i2++;
        }

        if (found) {
            // Create return array
            byte[] new_buf = new byte[i2];
            System.arraycopy(b2, 0, new_buf, 0, i2);
            return new_buf;
        } else {
            return null;
        }
    }
}

