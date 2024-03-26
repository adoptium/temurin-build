/*
 * ********************************************************************************
 * Copyright (c) 2023 Contributors to the Eclipse Foundation
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

package temurin.tools;

import java.io.FileOutputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HexFormat;

/**
 * This utility class binary replaces the given "hex" binary values with a new value.
 * Params:
 *   --inFile <input>
 *   --outFile <output>
 *   --hex "aa:aa-bb:bb" Replace aa:aa with bb:bb
 *   --string "string1=string2" Replace string1 with string2
 *   --pad <hh> Pad string replace with given hex byte value
 *   --firstOnly Only replace first instance
 *    --32bitBoundaryOnly Only replace if found on a 32bit boundary
 */
class BinRepl {

  protected BinRepl() { }

  // A simple static counter
  private static int replCounter = 0;

  public static void main(final String[] args) throws Exception {
    String inFile = null;
    String outFile = null;
    boolean firstOnly = false;
    boolean boundary32bitOnly = false;

    String[] hex = null;
    String[] str = null;
    String strPad = null;

    for (int i = 0; i < args.length; i++) {
      if (args[i].equals("--inFile")) {
        inFile = args[++i];
      } else if (args[i].equals("--outFile")) {
        outFile = args[++i];
      } else if (args[i].equals("--hex")) {
        hex = args[++i].split("-");
      } else if (args[i].equals("--string")) {
        str = args[++i].split("=");
      } else if (args[i].equals("--pad")) {
        strPad = args[++i];
      } else if (args[i].equals("--firstOnly")) {
        firstOnly = true;
      } else if (args[i].equals("--32bitBoundaryOnly")) {
        boundary32bitOnly = true;
      } else {
        System.out.println("Unknown option: " + args[i]);
        System.exit(1);
      }
    }

    if (inFile == null || outFile == null || (hex == null && str == null)) {
      System.out.println("Missing option, syntax:");
      System.out.println("BinRepl --inFile path --outFile path --hex aa:aa-bb:bb");
      System.out.println(
          "BinRepl --inFile path --outFile path --string \"17.0.6+10-LTS=17.0.6+10\" --pad 00");
      System.exit(1);
    }

    // Patch the inFile, writing result to outFile
    patchFile(inFile, outFile, hex, str, strPad, firstOnly, boundary32bitOnly);
  }

  // Patch the given inFile, writing result to outFile
  static void patchFile(final String inFile,
                        final String outFile,
                        final String[] hex,
                        final String[] str,
                        final String strPad,
                        final boolean firstOnly,
                        final boolean boundary32bitOnly) throws Exception {

    byte[] inBytes = Files.readAllBytes(Paths.get(inFile));

    HexFormat hexformat = HexFormat.ofDelimiter(":");

    byte[] outBytes;
    if (hex != null) {
      // Check for fuzzy bytes
      String[] aTmp = hex[0].replaceAll(" ", ":").trim().split(":");
      boolean[] fuzzyBytes = new boolean[aTmp.length];
      int i = 0;
      String hexA = "";
      for (String aHex : aTmp) {
        if (aHex.equals("?")) {
          fuzzyBytes[i] = true;
          hexA += "00";
        } else {
          fuzzyBytes[i] = false;
          hexA += aHex;
        }
        i++;
        if (i < aTmp.length) {
          hexA += ":";
        }
      }

      byte[] binA = hexformat.parseHex(hexA);
      byte[] binB = hexformat.parseHex(hex[1].replaceAll(" ", ":"));

      outBytes = binReplace(inBytes, binA, binB, fuzzyBytes, firstOnly, boundary32bitOnly);

      if (outBytes == null) {
        System.out.println("replacement hex not found in: " + inFile);
        System.exit(1);
      } else {
        System.out.println(
            "Number of occurrences of "
                + hex[0]
                + " replaced with "
                + hex[1]
                + " = "
                + replCounter);
      }
    } else {
      byte[] binA = str[0].getBytes("UTF-8");
      byte[] binB;
      if (str.length < 2) {
        binB = new byte[0];
      } else {
        binB = str[1].getBytes("UTF-8");
      }
      if (strPad != null) {
        if ((binA.length - binB.length) > 0) {
          // Need to pad binB
          byte[] hexPad = hexformat.parseHex(strPad);
          byte[] binC = new byte[binA.length];
          for (int i = 0; i < str[0].length(); i++) {
            if (i >= binB.length) {
              binC[i] = hexPad[0];
            } else {
              binC[i] = binB[i];
            }
          }
          binB = binC;
        }
      }

      boolean[] fuzzyBytes = new boolean[binA.length];
      for (int i = 0; i < fuzzyBytes.length; i++) {
        fuzzyBytes[i] = false;
      }

      outBytes = binReplace(inBytes, binA, binB, fuzzyBytes, firstOnly, boundary32bitOnly);

      if (outBytes == null) {
        System.out.println("replacement string not found in: " + inFile);
        System.exit(1);
      } else {
        if (str.length < 2) {
          System.out.println(
              "Number of occurrences of \"" + str[0] + "\" replaced with \"\" = " + replCounter);
        } else {
          System.out.println(
              "Number of occurrences of \""
                  + str[0]
                  + "\" replaced with \""
                  + str[1]
                  + "\" = "
                  + replCounter);
        }
      }
    }

    try (FileOutputStream fos = new FileOutputStream(outFile)) {
      fos.write(outBytes);
    }
  }

  // Replace byte[] x with y in b1 and return new array b2
  // Any fuzzyByte matches any value
  static byte[] binReplace(
      final byte[] b1,
      final byte[] x,
      final byte[] y,
      final boolean[] fuzzyByte,
      final boolean firstOnly,
      final boolean boundary32bitOnly) {
    byte[] b2 = new byte[b1.length + 4096]; // 4096 extra should be plenty!
    boolean found = false; // A match was found to replace

    int buf = x.length;
    int i2 = 0;
    for (int i1 = 0; i1 < b1.length; i1++) {
      boolean match = true;
      if (firstOnly && replCounter > 0) {
        match = false;
      } else if ((i1 + buf) > b1.length) {
        match = false;
      } else if (boundary32bitOnly && ((i1 % 4) != 0)) {
        match = false;
      } else {
        for (int j = 0; j < buf; j++) {
          if (b1[i1 + j] != x[j] && !fuzzyByte[j]) {
            match = false;
            break;
          }
        }
      }
      if (match) {
        found = true;
        replCounter++;
        for (int j = 0; j < y.length; j++) {
          b2[i2 + j] = y[j];
        }
        i1 += (buf - 1);
        i2 += (y.length - 1);
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
