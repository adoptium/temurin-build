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
 * This class searches for and replaces the VS_VERSION_INFO structure in a
 * Windows EXE/DLL, with a new set of property values.
 *
 * See: https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations
 */
class WinVersionInfoRepl {

    public static void main(String[] args) throws Exception {
        String inFile = null;
        String outFile = null;

        // VS_VERSIONINFO structure elements
        String   blockHeader = null;
        String[] companyName = null;
        String[] fileDesc = null;
        String[] fileVersion = null;
        String[] fullVersion = null;
        String[] internalName = null;
        String[] legalCopyright = null;
        String[] originalFilename = null;
        String[] productName = null;
        String[] productVersion = null;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--inFile")) {
                inFile = args[++i];
            } else if (args[i].equals("--outFile")) {
                outFile = args[++i];
            } else if (args[i].equals("--blockHeader")) {
                blockHeader = args[++i];
            } else if (args[i].equals("--companyName")) {
                companyName = args[++i].split(":");
            } else if (args[i].equals("--fileDesc")) {
                fileDesc = args[++i].split(":");
            } else if (args[i].equals("--fileVersion")) {
                fileVersion = args[++i].split(":");
            } else if (args[i].equals("--fullVersion")) {
                fullVersion = args[++i].split(":");
            } else if (args[i].equals("--internalName")) {
                internalName = args[++i].split(":");
            } else if (args[i].equals("--legalCopyright")) {
                legalCopyright = args[++i].split(":");
            } else if (args[i].equals("--originalFilename")) {
                originalFilename = args[++i].split(":");
            } else if (args[i].equals("--productName")) {
                productName = args[++i].split(":");
            } else if (args[i].equals("--productVersion")) {
                productVersion = args[++i].split(":");
            } else {
                System.out.println("Unknown option: "+args[i]);
                System.exit(1);
            }
        }

        if (inFile == null || outFile == null || blockHeader == null || companyName == null || fileDesc == null || fileVersion == null || fullVersion == null|| internalName == null || legalCopyright == null || originalFilename == null || productName == null || productVersion == null) {
            System.out.println("Missing option, syntax:");
            System.out.println("WinVersionInfoRepl --inFile path --outFile path --blockHeader a --companyName a:b --fileDesc a:b --fileVersion a:b --fullVersion a:b --internalName a:b --legalCopyright a:b --originalFilename a:b --productName a:b --productVersion a:b");
            System.exit(1);
        }

        byte[] verInfoA = constructVersionInfo(blockHeader, companyName[0], fileDesc[0], fileVersion[0], fullVersion[0], internalName[0], legalCopyright[0], originalFilename[0], productName[0], productVersion[0]);
        byte[] verInfoB = constructVersionInfo(blockHeader, companyName[1], fileDesc[1], fileVersion[1], fullVersion[1], internalName[1], legalCopyright[1], originalFilename[1], productName[1], productVersion[1]);

        HexFormat hex = HexFormat.ofDelimiter(":").withUpperCase();
        int i=0;
        for(; i<verInfoA.length/16; i++) {
            byte[] b = new byte[16];
            System.arraycopy(verInfoA, (i*16), b, 0, 16);
            String str = hex.formatHex(b);
            System.out.println(str); 
        }
        if ((verInfoA.length % 16) > 0) {
            byte[] b = new byte[verInfoA.length % 16];
            System.arraycopy(verInfoA, (i*16), b, 0, (verInfoA.length % 16));
            String str = hex.formatHex(b);
            System.out.println(str);
        }

        byte[] inBytes = Files.readAllBytes(Paths.get(inFile));

        byte[] outBytes = bin_replace(inBytes, verInfoA, verInfoB);
        if (outBytes == null) {
            System.out.println("VS_VERSION_INFO replacement not found in: "+inFile);
            System.exit(1);
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

    static byte[] constructVersionInfo(String blockHeader, String companyName, String fileDesc, String fileVersion, String fullVersion, String internalName, String legalCopyright, String originalFilename, String productName,  String productVersion) throws Exception {

        HexFormat hex = HexFormat.ofDelimiter(":");

        // See https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations
        byte[] vi = new byte[1024];
        int i=2; // Start from wValueLength

        // WORD wValueLength
        System.arraycopy(hex.parseHex("34:00"), 0, vi, i, 2);
        i += 2;

        // WORD wType
        System.arraycopy(hex.parseHex("00:00"), 0, vi, i, 2); 
        i += 2;

        // WCHAR szKey
        byte[] szKey = "VS_VERSION_INFO".getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, vi, i, szKey.length);
        i += szKey.length;
        // "sz" zero termination
        vi[i++] = 0;
        vi[i++] = 0;

        // WORD Padding1 32bit boundary
        int pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // Value : https://learn.microsoft.com/en-us/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo

        // DWORD dwSignature
        System.arraycopy(hex.parseHex("BD:04:EF:FE"), 0, vi, i, 4);
        i += 4;

        // DWORD dwStrucVersion
        System.arraycopy(hex.parseHex("00:00:01:00"), 0, vi, i, 4);
        i += 4;

        // fileVersion split. eg.17.0.6.0
        String[] fileVersionComps = fileVersion.split("\\.");
        // DWORD dwFileVersionMS
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[1]).intValue();
        vi[i++] = 0;
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[0]).intValue();
        vi[i++] = 0;

        // DWORD dwFileVersionLS
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[3]).intValue();
        vi[i++] = 0;
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[2]).intValue();
        vi[i++] = 0;

        // DWORD dwProductVersionMS
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[1]).intValue();
        vi[i++] = 0;
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[0]).intValue();
        vi[i++] = 0;

        // DWORD dwProductVersionLS
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[3]).intValue();
        vi[i++] = 0;
        vi[i++] = (byte)Integer.valueOf(fileVersionComps[2]).intValue();
        vi[i++] = 0;

        // DWORD dwFileFlagsMask = "03:00:00:00"
        System.arraycopy(hex.parseHex("03:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileFlags = "00:00:00:00"
        System.arraycopy(hex.parseHex("00:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileOS = "04:00:00:00"
        System.arraycopy(hex.parseHex("04:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileType = "01:00:00:00"
        System.arraycopy(hex.parseHex("01:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileSubtype = "00:00:00:00"
        System.arraycopy(hex.parseHex("00:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileDateMS = "00:00:00:00"
        System.arraycopy(hex.parseHex("00:00:00:00"), 0, vi, i, 4);
        i += 4;

        // DWORD dwFileDateLS = "00:00:00:00"
        System.arraycopy(hex.parseHex("00:00:00:00"), 0, vi, i, 4);
        i += 4;

        // WORD Padding2 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // Children: StringFileInfo + VarFileInfo

        // StringFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/stringfileinfo
        int stringFileInfoStart = i;
        
        // WORD wLength : fill at end
        i += 2;

        // WORD wValueLength
        System.arraycopy(hex.parseHex("00:00"), 0, vi, i, 2);
        i += 2;

        // WORD wType
        System.arraycopy(hex.parseHex("01:00"), 0, vi, i, 2);
        i += 2;

        // WCHAR szKey
        szKey = "StringFileInfo".getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, vi, i, szKey.length);
        i += szKey.length;
        // "sz" zero termination
        vi[i++] = 0;
        vi[i++] = 0;

        // WORD Padding2 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }
        
        // StringTable : https://learn.microsoft.com/en-us/windows/win32/menurc/stringtable
        int stringTableStart = i;

        // WORD wLength : fill at end
        i += 2;          

        // WORD wValueLength
        System.arraycopy(hex.parseHex("00:00"), 0, vi, i, 2);
        i += 2;

        // WORD wType
        System.arraycopy(hex.parseHex("01:00"), 0, vi, i, 2);
        i += 2;

        // WCHAR szKey
        szKey = blockHeader.getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, vi, i, szKey.length);
        i += szKey.length;
        // "sz" zero termination
        vi[i++] = 0;
        vi[i++] = 0;

        // WORD Padding 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // Children : Strings.. : https://learn.microsoft.com/en-us/windows/win32/menurc/string-str
        String[] strings = new String[] {"CompanyName", "FileDescription", "FileVersion", "Full Version", "InternalName", "LegalCopyright", "OriginalFilename", "ProductName",  "ProductVersion"};
        String[] stringValues = new String[] {companyName, fileDesc, fileVersion, fullVersion, internalName, legalCopyright, originalFilename, productName,  productVersion};
        for(int s=0; s<stringValues.length; s++) {
            // WORD Padding 32bit boundary
            pad = 4-(i % 4);
            if (pad < 4) {
                for( ; pad > 0; pad--) vi[i++] = 0;
            }

            int strStart = i;
            // WORD wLength : fill at end
            i += 2;

            szKey = strings[s].getBytes("UTF-16LE");
            byte[] szValue = stringValues[s].getBytes("UTF-16LE");

            // WORD wValueLength : value length including sz in WORDs
            int valueLen = (szValue.length+2)/2;
            vi[i++] = (byte)(valueLen % 0x100);
            vi[i++] = (byte)(valueLen / 0x100);

            // WORD wType
            System.arraycopy(hex.parseHex("01:00"), 0, vi, i, 2);
            i += 2;

            // WCHAR szKey
            System.arraycopy(szKey, 0, vi, i, szKey.length);
            i += szKey.length;
            // "sz" zero termination
            vi[i++] = 0;
            vi[i++] = 0;

            // WORD Padding 32bit boundary
            pad = 4-(i % 4);
            if (pad < 4) {
                for( ; pad > 0; pad--) vi[i++] = 0;
            }

            // WCHAR Value
            System.arraycopy(szValue, 0, vi, i, szValue.length);
            i += szValue.length;
            // "sz" zero termination
            vi[i++] = 0;
            vi[i++] = 0;

            // Fill String WORD wLength
            vi[strStart] = (byte)((i-strStart) % 0x100);
            vi[strStart+1] = (byte)((i-strStart) / 0x100);
        }

        // Fill StringTable WORD wLength
        vi[stringTableStart] = (byte)((i-stringTableStart) % 0x100);
        vi[stringTableStart+1] = (byte)((i-stringTableStart) / 0x100);

        // Fill StringFileInfo WORD wLength
        vi[stringFileInfoStart] = (byte)((i-stringFileInfoStart) % 0x100);
        vi[stringFileInfoStart+1] = (byte)((i-stringFileInfoStart) / 0x100);

        // WORD Padding 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // VarFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/varfileinfo
        int varFileStart = i;

        // WORD wLength : fill at end
        i += 2;

        // WORD wValueLength
        System.arraycopy(hex.parseHex("00:00"), 0, vi, i, 2);
        i += 2;

        // WORD wType
        System.arraycopy(hex.parseHex("01:00"), 0, vi, i, 2);
        i += 2;

        // WCHAR szKey
        szKey = "VarFileInfo".getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, vi, i, szKey.length);
        i += szKey.length;
        // "sz" zero termination
        vi[i++] = 0;
        vi[i++] = 0;

        // WORD Padding2 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // Var : https://learn.microsoft.com/en-us/windows/win32/menurc/var-str
        int varStart = i;
            
        // WORD wLength : fill at end
        i += 2;
                
        // WORD wValueLength : 4 byte DWORD
        System.arraycopy(hex.parseHex("04:00"), 0, vi, i, 2);
        i += 2;
                
        // WORD wType 
        System.arraycopy(hex.parseHex("00:00"), 0, vi, i, 2);
        i += 2;
                
        // WCHAR szKey
        szKey = "Translation".getBytes("UTF-16LE");
        System.arraycopy(szKey, 0, vi, i, szKey.length);
        i += szKey.length;
        // "sz" zero termination
        vi[i++] = 0;
        vi[i++] = 0;
                
        // WORD Padding2 32bit boundary
        pad = 4-(i % 4);
        if (pad < 4) {
            for( ; pad > 0; pad--) vi[i++] = 0;
        }

        // DWORD Value : language & codepage pair = "09:04:b0:04"
        System.arraycopy(hex.parseHex("09:04:b0:04"), 0, vi, i, 4);
        i += 4;

        // Fill Var WORD wLength
        vi[varStart] = (byte)((i-varStart) % 0x100);
        vi[varStart+1] = (byte)((i-varStart) / 0x100);

        // Fill varFileStart WORD wLength
        vi[varFileStart] = (byte)((i-varFileStart) % 0x100);
        vi[varFileStart+1] = (byte)((i-varFileStart) / 0x100);

        // Fill VS_VERSION_INFO WORD wLength
        vi[0] = (byte)(i % 0x100);
        vi[1] = (byte)(i / 0x100);

        // Create return array
        byte[] constructed = new byte[i];
        System.arraycopy(vi, 0, constructed, 0, i);

        return constructed;
    }
}

