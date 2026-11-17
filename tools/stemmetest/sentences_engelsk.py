"""Dansk tekst med engelske ord: (kategori, skrevet tekst, tekst som den skal høres).

Bruges til at måle, om en stemme udtaler engelske navne og fagord, så de kan genkendes.
Kategorien siger, om ordene står på en af udtalelisterne ("liste"), er bøjet ("bøjet"),
eller er ord, der aldrig har været afprøvet enkeltvis ("uset") – de sidste viser, hvor langt
listerne rækker ud over det, de er lavet på.
"""
SENTENCES = [
    ("liste", "Jeg åbner Chrome hver morgen.", "jeg åbner chrome hver morgen"),
    ("liste", "Vi gemmer alle filer i cloud.", "vi gemmer alle filer i cloud"),
    ("liste", "Husk at lave en update i aften.", "husk at lave en update i aften"),
    ("liste", "Butikken har fået en ny website.", "butikken har fået en ny website"),
    ("liste", "Hun så en video på YouTube.", "hun så en video på youtube"),
    ("liste", "Min iPhone er løbet tør for strøm.", "min iphone er løbet tør for strøm"),
    ("liste", "Læreren viste en PowerPoint i timen.", "læreren viste en powerpoint i timen"),
    ("liste", "Skriv til mig på Slack.", "skriv til mig på slack"),
    ("liste", "Tak for din feedback på opgaven.", "tak for din feedback på opgaven"),
    ("liste", "Næsten alle børn har en smartphone.", "næsten alle børn har en smartphone"),
    ("liste", "Du skal bruge dit login for at komme ind.", "du skal bruge dit login for at komme ind"),
    ("liste", "Han bruger meget tid på gaming.", "han bruger meget tid på gaming"),
    ("liste", "Hun lagde et billede på Instagram.", "hun lagde et billede på instagram"),
    ("liste", "Send mig en besked på Messenger.", "send mig en besked på messenger"),
    ("liste", "Jeg spurgte ChatGPT om hjælp.", "jeg spurgte chatgpt om hjælp"),
    ("liste", "Åbn siden i Safari i stedet.", "åbn siden i safari i stedet"),
    ("liste", "Appen findes også til Android.", "appen findes også til android"),
    ("liste", "Tag et screenshot af fejlen.", "tag et screenshot af fejlen"),
    ("liste", "Dokumentet ligger i Google Docs.", "dokumentet ligger i google docs"),
    ("liste", "Firmaet flytter sine servere til Azure.", "firmaet flytter sine servere til azure"),
    ("bøjet", "Chromes nye faner er hurtigere.", "chromes nye faner er hurtigere"),
    ("bøjet", "Der kom to updates i denne uge.", "der kom to updates i denne uge"),
    ("bøjet", "Alle elevernes smartphones blev samlet ind.", "alle elevernes smartphones blev samlet ind"),
    ("bøjet", "Det er et cloud-valg, vi må træffe.", "det er et cloud valg vi må træffe"),
    ("uset", "Vi holder et meeting om projektets deadline.", "vi holder et meeting om projektets deadline"),
    ("uset", "Jeg hørte en podcast om streaming.", "jeg hørte en podcast om streaming"),
    ("uset", "Hun købte en ny laptop og et keyboard.", "hun købte en ny laptop og et keyboard"),
    ("uset", "Min manager bad om en statusrapport og et dashboard.", "min manager bad om en statusrapport og et dashboard"),
    ("uset", "Vi brainstormer på et whiteboard efter frokost.", "vi brainstormer på et whiteboard efter frokost"),
    ("uset", "Download filen, og upload den til serveren.", "download filen og upload den til serveren"),
]
