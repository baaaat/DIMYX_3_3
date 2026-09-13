import java.nio.file.*;
import java.io.*;
import processing.mode.java.preproc.*;

class Preprocess {
  public static void main(String[] args) throws Exception {
    try (Writer out = Files.newBufferedWriter(Path.of(args[1]))) {
      var result = PdePreprocessor.builderFor("DIMYX_3_3").build().write(out, Files.readString(Path.of(args[0])));
      if (!result.getPreprocessIssues().isEmpty()) throw new AssertionError(result.getPreprocessIssues());
    }
  }
}
