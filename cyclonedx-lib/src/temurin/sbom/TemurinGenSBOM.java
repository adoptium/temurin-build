/*
################################################################################
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
import org.cyclonedx.CycloneDxSchema.Version;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Component;
import org.cyclonedx.generators.json.BomJsonGenerator;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {
    private TemurinGenSBOM() {
    }

    /**
     * Main entry.
     * @param args Arguments for sbom operation.
     */
    public static void main(final String[] args) {
        System.out.print("TemurinGenSBOM:");
        for (String arg : args) {
            System.out.print(" " + arg);
        }
        System.out.println("");

        Bom bom = createTestBom();
        String json = generateBomJson(bom);

        System.out.println("SBOM: " + json);
    }

    static Bom createTestBom() {
        Bom bom = new Bom();

        Component comp1 = new Component();
        comp1.setName("TestComponent");
        comp1.setVersion("1.0.0");
        comp1.setType(Component.Type.APPLICATION);
        comp1.setAuthor("Adoptium");

        bom.addComponent(comp1);

        return bom;
    }

    static String generateBomJson(final Bom bom) {
        BomJsonGenerator bomGen = BomGeneratorFactory.createJson(Version.VERSION_13, bom);

        String json = bomGen.toJsonString();

        return json;
    }
}
