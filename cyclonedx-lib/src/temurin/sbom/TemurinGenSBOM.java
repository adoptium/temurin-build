/*# Licensed under the Apache License, Version 2.0 (the "License");
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

import org.cyclonedx.BomGeneratorFactory;
import org.cyclonedx.CycloneDxSchema.Version;
import org.cyclonedx.model.*;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.generators.json.BomJsonGenerator;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {

    private static String fileName;

    private static String name;
    private static String version;
    private static String value;
    private static String url;
    private static String hashes;
    private static Bom bom;
    private static  String cmd;
    private static String comment;
    private static Metadata meta = new Metadata();
    private static Property prop2 = new Property();
    private static Component comp = new Component();
    private List<Component> comp1 = new ArrayList<>();
    private static List<Property> prop = new ArrayList<>();
    private static List<Hash> hash = new ArrayList<>();
    private static Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
    private static  ExternalReference extRef = new ExternalReference();
    private static FileWriter file;

    private TemurinGenSBOM() {
    }

    public static void main(final String[] args) {


        for (int i = 0; i < args.length; i++) {

            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
            } else if (args[i].equals("--version")) {
                version = args[++i];
            } else if (args[i].equals("--name")) {
                name = args[++i];
            } else if (args[i].equals("--value")) {
                value = args[++i];
            } else if (args[i].equals("--url")) {
                url = args[++i];
            } else if (args[i].equals("--comment")) {
                comment = args[++i];
            } else if (args[i].equals("--createNewSBOM")) {
                cmd = "createNewSBOM";
            } else if (args[i].equals("--addMetadata")) {        //This is Metadata Component. We can set "name" for Metadata->Component.
                cmd = "addMetadata";
            } else if (args[i].equals("--addMetadataProp")) {   //This is MetaData Component --> Property -> name-value: os, arch, variant, scmRef, buildRef, full_version_output, makejdk_any_platform_args
                cmd = "addMetadataProperty";
            } else if (args[i].equals("--addComponent")) {      //This is Components->Property: will add name-value.
                cmd = "addComponent";
            } else if (args[i].equals("--addComponentProp")) {  //This is Components->Property: will add name-value.
                cmd = "addComponentProp";
            } else if (args[i].equals("--addExternalRef")) {
                cmd = "addExtRef";
            } else if (args[i].equals("--addComExtRef")) {
                cmd = "addComExtRef";
            }
        }
        switch (cmd) {
            case "createNewSBOM": {                           //Creates JSON file
                Bom bom = createBom(name, version);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addMetadata": {                             //This is Metadata Component --> name
                Bom bom = readJSONfile();
                bom = addMetadata(bom, name);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addMetadataProperty": {                     //This is MetaData--> Component --> Property -> name-value:
                Bom bom = readJSONfile();
                bom = addMetadataProperty(bom, name, value);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addComponent": {                              //This adds Component with component name
                Bom bom = readJSONfile();
                bom = addComponent(bom, name);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addComponentProp": {                             //This adds Components with name-value pairs to List
                Bom bom = readJSONfile();
                bom = addComponentProperty(bom, name, value);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addExtRef": {                                    //This adds external Reference
                Bom bom = readJSONfile();
                bom = addExternalReference(bom, url, comment);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;

            case "addComponentExtRef": {                                 //This adds external Reference to Component
                Bom bom = readJSONfile();
                bom = addComponentExternalReference(bom, url, hashes, comment);
                String json = generateBomJson(bom);
                writeJSONfile(json, fileName);
                System.out.println("SBOM: " + json);
            } break;
            default: {
                System.out.println("Please enter a command.");
            }
        }
    }

    static Bom createBom(String name, String version) {        //Create SBOM, test.JSON file
        Bom bom = new Bom();
        System.out.println(bom.getBomFormat());
        Component comp = new Component();
        comp.setName(name);
        comp.setVersion(version);
        comp.setType(Component.Type.APPLICATION);
        comp.setGroup("Eclipse Temurin");
        comp.setAuthor("Vendor: Adoptium");
        bom.addComponent(comp);
        return bom;
    }
    static Bom addMetadata(Bom bom, String name) {               //Method to store metadata -->  name
        comp.setName(name);
        comp.setType(Component.Type.APPLICATION);
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName("Eclipse Foundation");
        org.setUrls(Collections.singletonList("https://www.eclipse.org/"));
        meta.setManufacture(org);
        meta.setComponent(comp);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataProperty(Bom bom, String name, String value) {     //Method to store metadata --> Properties List --> name-values
        meta = bom.getMetadata();
        prop1.setName(name);
        prop1.setValue(value);
        meta.addProperty(prop1);
        bom.setMetadata(meta);
        return bom;
    }

    static Bom addComponent (Bom bom, String name) {                    //Method to store Component -> name
        comp.setType(Component.Type.APPLICATION);
        comp.setName(name);
        bom.addComponent(comp);
        return bom;
    }
    static Bom addComponentProperty(Bom bom, String name, String value) {     //Method to store Component-> Property-> name-value pairs
        prop1.setName(name);
        prop1.setValue(value);
        prop.add(prop1);
        comp.setProperties(prop);
        bom.addProperty(prop1);
        return bom;
    }
    static Bom addExternalReference(Bom bom, String url, String comment) {   //Method to store externalReferences: dependency_version_alsa
        hash.add(hash1);
        extRef.add(hash1);
        extRef.setUrl(url);
        extRef.setComment(comment);
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        bom.addExternalReference(extRef);
        return bom;
    }

    static Bom addComExternalReference(Bom bom, String url, String hashes, String comment) {  //Method to store externalReferences to store: openjdk_source
        hash.add(hash1);
        extRef.setHashes(hash);
        extRef.addHash(hash1);
        extRef.setUrl(url);
        extRef.setComment(comment); //"openjdk_source"
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        comp.addExternalReference(extRef);
        bom.addComponent(comp);
        return bom;
    }

    static String generateBomJson(final Bom bom) {
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(Version.VERSION_13, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static void writeJSONfile(String json, String fileName) {          //Creates testJson.json file
        try {
            file = new FileWriter(fileName);
            file.write(json);
            file.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    static Bom readJSONfile() { 	                               //Returns parse bom
        try {
            FileReader reader = new FileReader(fileName);
            JsonParser parser = new JsonParser();
            bom = parser.parse(reader);
        }
        catch (Exception e) {
            e.printStackTrace();
        }
        return bom;
    }
}
