#include "Fasta_reader.hpp"
#include "sequenceUtil.hpp"
#include "stacktrace.hpp"
#include <algorithm>

//constructor
Fasta_reader::Fasta_reader (string filename) {
  
    this->_hasNext = false;
    
    if (filename == "-") {
        filename = "/dev/fd/0"; // read from stdin
    }
    this->_filereader.open(filename.c_str());
    if (! _filereader.is_open()) {
        throw(stacktrace() + "\n\nError, cannot open file " + filename );
    }
    
    // primer reader to first fasta header
    getline(this->_filereader, this->_lastline);
    while ((! this->_filereader.eof()) && this->_lastline[0] != '>') {
        getline(this->_filereader, this->_lastline);
    }
    
    
}

bool Fasta_reader::hasNext() {
    bool ret;
    
    #pragma omp critical (FileReader)
    {
        ret = !(this->_filereader.eof());
    }
    return ret;
}


Fasta_entry Fasta_reader::getNext() {
    
    string sequence;
    string header;
    bool ret;

    #pragma omp critical (FileReader)
    {
        header = this->_lastline;
        
        ret = !(this->_filereader.eof());
        if (ret == true)
        {
            this->_lastline = "";
            while ((! this->_filereader.eof()) && this->_lastline[0] != '>') {
                getline(this->_filereader, this->_lastline);
                if (this->_lastline[0] != '>') {
                    sequence += this->_lastline;
                }
            }
        }
    }
    
    if (ret == true)
    {
        sequence = remove_whitespace(sequence);
        transform(sequence.begin(), sequence.end(), sequence.begin(), ::toupper);
        Fasta_entry fe(header, sequence);
        return(fe);
    } else {
        Fasta_entry fe("", "");
        return(fe);
    }
}

map<string,string> Fasta_reader::retrieve_all_seqs_hash() {
    
    map<string,string> all_seqs_hash;
    
    while (this->hasNext()) {
        Fasta_entry f = this->getNext();
        string acc = f.get_accession();
        string seq = f.get_sequence();
        
        all_seqs_hash[acc] = seq;
    }
    
    return(all_seqs_hash);
}
