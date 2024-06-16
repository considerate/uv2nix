from edifice import (
    App,
    Label,
    Window,
    component,
)

@component
def Main(self):
    with Window(title="example window"):
        Label("Hello")

if __name__ == "__main__":
    App(Main(), application_name="Example App").start()
