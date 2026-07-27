"""Entry point: python -m joust_manager"""
from joust_manager.cli.app import App


def main() -> None:
    try:
        app = App()
        app.run()
    except KeyboardInterrupt:
        print("\n\n  Farewell, knight. Until the next tourney.\n")
    except EOFError:
        print("\n\n  Farewell, knight. Until the next tourney.\n")


if __name__ == "__main__":
    main()
