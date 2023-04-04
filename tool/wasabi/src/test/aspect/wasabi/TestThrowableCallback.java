package wasabi;

import java.net.SocketTimeoutException;

import org.junit.Test;
import static org.junit.jupiter.api.Assertions.assertThrows;

public class TestThrowableCallback {

    @Test
    public void testSocketTimeoutException() throws Exception {
        ThrowableCallback callback = new ThrowableCallback();

        assertThrows(SocketTimeoutException.class, () -> {
            throw new SocketTimeoutException("Test SocketTimeoutException");
        });
    }

}
