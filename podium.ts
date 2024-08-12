interface Element {
    kind: never;
    path: string | null;
    offset: number | null;
}
interface InlineElement extends Element {
    kind: 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' | 'K' | 'L' | 'M'
        | 'N' | 'O' | 'P' | 'Q' | 'R' | 'S' | 'T' | 'U' | 'V' | 'W' | 'X' | 'Y' | 'Z';
}
interface BlockElement extends Element {
    kind: 'pod'
        | 'cut'
        | 'encoding'
        | 'over'
        | 'item'
        | 'back'
        | 'verbatim'
        | 'for'
        | 'head1'
        | 'head2'
        | 'head3'
        | 'head4';
}