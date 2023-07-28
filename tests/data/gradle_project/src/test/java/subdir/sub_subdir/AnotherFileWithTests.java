package subdir.sub_subdir;

import org.junit.Test;

import static org.junit.Assert.*;

public class AnotherFileWithTests {
    @Test
    public void passing_test() {
        assertTrue(true);
    }

    @Test
    public void failing_test() {
        assertTrue(false);
    }
}
