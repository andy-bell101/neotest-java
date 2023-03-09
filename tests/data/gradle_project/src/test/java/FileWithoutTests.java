import static org.assertj.core.api.Assertions.*;

public class FileWithoutTests {
    public void passing_test() {
        assertThat(true).isEqualTo(true);
    }

    public void failing_test() {
        assertThat(true).isEqualTo(false);
    }
}
