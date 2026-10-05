@dataclass
class Greeter:
    def greet(self, name="world"):  # say hi
        """Multi-line
        docstring"""
        return f"Hi {name}\n" if name is not None else 0x1F
