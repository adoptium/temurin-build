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

import org.cyclonedx.BomGeneratorFactory;
import org.cyclonedx.CycloneDxSchema;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Metadata;
import org.cyclonedx.model.Property;
import org.cyclonedx.model.Component;
import org.cyclonedx.model.ExternalReference;
import org.cyclonedx.model.Hash;
import org.cyclonedx.model.OrganizationalEntity;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.generators.json.BomJsonGenerator;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.Collections;
import java.util.List;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {

    private static boolean verbose = false;

    private TemurinGenSBOM() {
    }
    /**
     * Main entry.
     * @param args Arguments for sbom operation.
     */

    public static void main(final String[] args) {
        String name = null;
        String value = null;
        String url = null;
        String version = null;
        String cmd = null;
        String comment = null;
        String fileName = null;
        String hashes = null;
        String compName = null;
        String description = null;

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
            } else if (args[i].equals("--hashes")) {
                hashes = args[++i];
            } else if (args[i].equals("--compName")) {
                compName = args[++i];
            } else if (args[i].equals("--description")) {
                description = args[++i];
            } else if (args[i].equals("--createNewSBOM")) {
                cmd = "createNewSBOM";
            } else if (args[i].equals("--addMetadata")) {        // Metadata Component. We can set "name" for Metadata->Component.
                cmd = "addMetadata";
            } else if (args[i].equals("--addMetadataProp")) {    // MetaData Component --> Property -> name-value
                cmd = "addMetadataProperty";
            } else if (args[i].equals("--addComponent")) {       // Components->Property: will add name-value.
                cmd = "addComponent";
            } else if (args[i].equals("--addComponentProp")) {  // Components->Property: will add name-value.
                cmd = "addComponentProp";
            } else if (args[i].equals("--addExternalReference")) {
                cmd = "addExternalReference";
            } else if (args[i].equals("--addComponentExtRef")) {
                cmd = "addComponentExternalReference";
            } else if (args[i].equals("--verbose")) {
                verbose = true;
            }
        }
        switch (cmd) {
            case "createNewSBOM":                            // Creates JSON file
                Bom bom = createBom(name, version);
                writeJSONfile(bom, fileName);
                break;

            case "addMetadata":                              // Adds Metadata Component --> name
                bom = addMetadata(name, fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addMetadataProperty":                     // Adds MetaData--> Component --> Property --> name-value:
                bom = addMetadataProperty(name, value, fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addComponent":                            // Adds Component
                bom = addComponent(compName, name, value, description, fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addComponentProp":                       // Adds Components --> name-value pairs
                bom = addComponentProperty(compName, name, value, fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addExternalReference":                                     // Adds external Reference
                bom = addExternalReference(hashes, url, comment, fileName);
                writeJSONfile(bom, fileName);
                break;

            case "addComponentExternalReference":                                  // Adds external Reference to component
                bom = addComponentExternalReference(hashes, url, comment,  fileName);
                writeJSONfile(bom, fileName);
                break;
            default:
                System.out.println("Please enter a command.");
        }
    }

    static Bom createBom(final String name, final String version) {        // Create SBOM, test.JSON file
        Bom bom = new Bom();
        Component comp = new Component();
        comp.setName(name);
        comp.setVersion(version);
        comp.setType(Component.Type.FRAMEWORK);
        comp.setGroup("Eclipse Temurin");
        comp.setAuthor("Vendor: Eclipse");
        bom.addComponent(comp);
        return bom;
    }
    static Bom addMetadata(final String name, final String fileName) {          // Method to store metadata -->  name
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        Component comp = new Component();
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName("Eclipse Foundation");
        org.setUrls(Collections.singletonList("https://www.eclipse.org/"));
        meta.setManufacture(org);
        meta.setComponent(comp);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addMetadataProperty(final String name, final String value, final String fileName) {     // Method to store metadata --> Properties List --> name-values
        Bom bom = readJSONfile(fileName);
        Metadata meta = new Metadata();
        Property prop1 = new Property();
        meta = bom.getMetadata();
        prop1.setName(name);
        prop1.setValue(value);
        meta.addProperty(prop1);
        bom.setMetadata(meta);
        return bom;
    }
    static Bom addComponent(final String compName, final String name, final String value, final String description, final String fileName) {      // Method to store Component --> name & single name-value pair
        Bom bom = readJSONfile(fileName);
        Component comp = new Component();
        comp.setName(compName);
        comp.setDescription(description);
        bom.addComponent(comp);
        return bom;
    }
    static Bom addComponentProperty(final String compName, final String name, final String value, final String fileName) {     // Method to add Component --> Property --> name-value pairs
        Bom bom = readJSONfile(fileName);
        List<Component> componentArrayList = bom.getComponents();
        for (Component item : componentArrayList) {
            if (item.getName().equals(compName)) {
                    Property prop1 = new Property();
                    prop1.setName(name);
                    prop1.setValue(value);
                    item.addProperty(prop1);
            }
        }
        return bom;
    }
    static Bom addExternalReference(final String hashes, final String url, final String comment, final String fileName) {   // Method to store externalReferences: dependency_version_alsa
        Bom bom = readJSONfile(fileName);
        ExternalReference extRef = new ExternalReference();
        Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
        extRef.addHash(hash1);
        extRef.setUrl(url);
        extRef.setComment(comment);
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        bom.addExternalReference(extRef);
        return bom;
    }

    static Bom addComponentExternalReference(final String hashes, final String url, final String comment, final String fileName) {  // Method to store externalReferences to store: openjdk_source
        Bom bom = readJSONfile(fileName);
        ExternalReference extRef = new ExternalReference();
        Hash hash1 = new Hash(Hash.Algorithm.SHA3_256, hashes);
        Component comp = new Component();
        extRef.addHash(hash1);
        extRef.setUrl(url);
        extRef.setComment(comment); //"openjdk_source"
        extRef.setType(ExternalReference.Type.BUILD_SYSTEM);
        comp.addExternalReference(extRef);
        bom.addComponent(comp);
        return bom;
    }

    static String generateBomJson(final Bom bom) {
        // Use schema v14: https://cyclonedx.org/schema/bom-1.4.schema.json
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(CycloneDxSchema.Version.VERSION_14, bom);
        String json = bomGen.toJsonString();
        return json;
    }

    static void writeJSONfile(final Bom bom, final String fileName) {          // Creates testJson.json file
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

    static Bom readJSONfile(final String fileName) { 	                               // Returns parse bom
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
}
